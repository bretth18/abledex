//
//  ProjectScanner.swift
//  abledex
//
//  Created by Brett Henderson on 12/14/25.
//

import Foundation
import CryptoKit

enum ScanProgress: Sendable {
    case starting
    case discovering(location: String)
    case parsing(current: Int, total: Int, projectName: String)
    case completed(projectCount: Int, duration: TimeInterval)
    case failed(Error)

    var description: String {
        switch self {
        case .starting:
            return "starting"
        case .discovering(let location):
            return "discovering-\(location)"
        case .parsing(let current, _, let name):
            return "parsing-\(current)-\(name)"
        case .completed(let count, _):
            return "completed-\(count)"
        case .failed:
            return "failed"
        }
    }
}

/// Tracks .als file paths already claimed by a scan task so that overlapping
/// locations (e.g. ~/Music and ~/Music/Ableton, or user-added nested folders)
/// never process the same project twice. Duplicate processing races on insert:
/// both tasks fetch "no existing record", then both insert with fresh UUIDs,
/// hitting the UNIQUE(alsFilePath) constraint or churning record IDs.
private actor ScanCoordinator {
    private var claimedPaths: Set<String> = []

    /// Returns the subset of `paths` not yet claimed by another location's scan,
    /// and claims them for the caller.
    func claim(_ paths: [String]) -> Set<String> {
        var granted: Set<String> = []
        granted.reserveCapacity(paths.count)
        for path in paths where claimedPaths.insert(path).inserted {
            granted.insert(path)
        }
        return granted
    }
}

final class ProjectScanner: Sendable {
    private let database: AppDatabase
    private let crawler = FileSystemCrawler()

    nonisolated init(database: AppDatabase) {
        self.database = database
    }

    func scanAllLocations(
        forceReparse: Bool = false,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> Int {
        let startTime = Date()
        progress(.starting)

        let locations = try await database.fetchEnabledLocations()

        // Dedupes discovered .als paths across concurrently scanned locations
        // in case any locations overlap (e.g. one is nested inside another).
        let coordinator = ScanCoordinator()

        // Scan all locations in parallel
        let totalProjects = try await withThrowingTaskGroup(of: Int.self) { group in
            for location in locations {
                group.addTask {
                    try await self.scanLocation(
                        location,
                        forceReparse: forceReparse,
                        coordinator: coordinator,
                        progress: progress
                    )
                }
            }

            var total = 0
            for try await count in group {
                total += count
            }
            return total
        }

        let duration = Date().timeIntervalSince(startTime)
        progress(.completed(projectCount: totalProjects, duration: duration))

        return totalProjects
    }

    func scanLocation(
        _ location: LocationRecord,
        forceReparse: Bool = false,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> Int {
        try await scanLocation(location, forceReparse: forceReparse, coordinator: nil, progress: progress)
    }

    private func scanLocation(
        _ location: LocationRecord,
        forceReparse: Bool,
        coordinator: ScanCoordinator?,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> Int {
        let locationURL = URL(fileURLWithPath: location.path)

        progress(.discovering(location: location.displayName))

        // Discovery happens synchronously but is fast (throws on cancellation)
        var discoveredProjects = try crawler.findProjects(in: locationURL)

        // When scanning multiple locations concurrently, only process paths
        // this location claims first — overlapping locations discover the same
        // files and would otherwise race on insert.
        if let coordinator {
            let claimed = await coordinator.claim(discoveredProjects.map { $0.alsFilePath.path })
            discoveredProjects = discoveredProjects.filter { claimed.contains($0.alsFilePath.path) }
        }

        let total = discoveredProjects.count

        guard total > 0 else {
            try await database.updateLocationProjectCount(id: location.id, count: 0)
            return 0
        }

        // Fetch existing projects to preserve user metadata
        let alsFilePaths = discoveredProjects.map { $0.alsFilePath.path }
        let existingProjects = try await database.fetchProjects(byAlsFilePaths: alsFilePaths)

        // Parse in batches to avoid memory pressure
        var processed = 0
        let batchSize = 50

        for batch in stride(from: 0, to: total, by: batchSize) {
            try Task.checkCancellation()

            let end = min(batch + batchSize, total)
            let batchProjects = Array(discoveredProjects[batch..<end])

            // Parse batch concurrently, skipping unchanged files
            let records = await withTaskGroup(of: ProjectRecord?.self) { group in
                for discovered in batchProjects {
                    let existing = existingProjects[discovered.alsFilePath.path]

                    // Skip files that haven't changed since last index.
                    // Exception: records flagged with missing samples are re-verified
                    // every scan — earlier detection had false positives, and the user
                    // may have restored the files; either way the flag should self-heal.
                    if !forceReparse,
                       let existing = existing,
                       !existing.hasMissingSamples,
                       abs(existing.filesystemModifiedDate.timeIntervalSince(discovered.modifiedDate)) < 1.0 {
                        continue
                    }

                    group.addTask {
                        self.parseProject(discovered, existing: existing)
                    }
                }

                var results: [ProjectRecord] = []
                for await record in group {
                    if let record = record {
                        results.append(record)
                    }
                }
                return results
            }

            // Save structured: awaited before the next batch starts, so
            // cancellation propagates and no save outlives this scope.
            if !records.isEmpty {
                try await database.saveProjects(records)
            }

            processed += batchProjects.count
            if let lastProject = batchProjects.last {
                progress(.parsing(current: processed, total: total, projectName: lastProject.projectName))
            }
        }

        try await database.updateLocationProjectCount(id: location.id, count: processed)
        return processed
    }

    func scanSingleProject(alsFilePath: String) async throws -> ProjectRecord? {
        let url = URL(fileURLWithPath: alsFilePath)
        let folderURL = url.deletingLastPathComponent()

        guard FileManager.default.fileExists(atPath: alsFilePath) else { return nil }

        let attrs = try FileManager.default.attributesOfItem(atPath: alsFilePath)
        let modifiedDate = (attrs[.modificationDate] as? Date) ?? Date()
        let createdDate = (attrs[.creationDate] as? Date) ?? modifiedDate

        let projectName = url.deletingPathExtension().lastPathComponent
        let sourceVolume = FileSystemCrawler.volumeName(for: url)

        let discovered = DiscoveredProject(
            folderPath: folderURL,
            alsFilePath: url,
            projectName: projectName,
            sourceVolume: sourceVolume,
            createdDate: createdDate,
            modifiedDate: modifiedDate
        )

        let existingProjects = try await database.fetchProjects(byAlsFilePaths: [alsFilePath])
        let existing = existingProjects[alsFilePath]

        guard let record = parseProject(discovered, existing: existing) else { return nil }

        try await database.saveProjects([record])
        return record
    }

    private nonisolated func parseProject(_ discovered: DiscoveredProject, existing: ProjectRecord?) -> ProjectRecord? {
        do {
            let parsedData = try ALSParser().parse(alsFilePath: discovered.alsFilePath)

            let samplePathsJSON = (try? JSONEncoder().encode(parsedData.samplePaths))
                .flatMap { String(data: $0, encoding: .utf8) }
            let pluginsJSON = (try? JSONEncoder().encode(parsedData.plugins))
                .flatMap { String(data: $0, encoding: .utf8) }
            let musicalKeysJSON = (try? JSONEncoder().encode(parsedData.musicalKeys))
                .flatMap { String(data: $0, encoding: .utf8) }

            // Calculate file hash for duplicate detection
            let fileHash = calculateFileHash(url: discovered.alsFilePath)

            // Resolve sample references against the filesystem (cheap stat calls,
            // already off the main thread). Empty references -> false.
            let hasMissingSamples = Self.detectMissingSamples(
                references: parsedData.sampleFileReferences,
                projectFolder: discovered.folderPath
            )

            // Preserve user metadata from existing record, or use defaults for new projects
            return ProjectRecord(
                id: existing?.id ?? UUID(),
                name: discovered.projectName,
                folderPath: discovered.folderPath.path,
                alsFilePath: discovered.alsFilePath.path,
                sourceVolume: discovered.sourceVolume,
                createdDate: discovered.createdDate,
                modifiedDate: discovered.modifiedDate,
                filesystemModifiedDate: discovered.modifiedDate,
                bpm: parsedData.bpm,
                timeSignatureNumerator: parsedData.timeSignatureNumerator,
                timeSignatureDenominator: parsedData.timeSignatureDenominator,
                audioTrackCount: parsedData.audioTrackCount,
                midiTrackCount: parsedData.midiTrackCount,
                returnTrackCount: parsedData.returnTrackCount,
                totalTrackCount: parsedData.audioTrackCount + parsedData.midiTrackCount + parsedData.returnTrackCount,
                abletonVersion: parsedData.abletonVersion,
                abletonMinorVersion: parsedData.abletonMinorVersion,
                duration: parsedData.duration,
                samplePathsJSON: samplePathsJSON,
                pluginsJSON: pluginsJSON,
                musicalKeysJSON: musicalKeysJSON,
                hasMissingSamples: hasMissingSamples,
                fileHash: fileHash,
                lastIndexedAt: Date(),
                userTagsJSON: existing?.userTagsJSON,
                userNotes: existing?.userNotes,
                completionStatus: existing?.completionStatus ?? .none,
                colorLabel: existing?.colorLabel ?? .none,
                isFavorite: existing?.isFavorite ?? false,
                lastOpenedAt: existing?.lastOpenedAt,
                collectionID: existing?.collectionID
            )
        } catch {
            print("Failed to parse \(discovered.projectName): \(error.localizedDescription)")
            return nil
        }
    }

    /// Returns true if at least one referenced sample file cannot be found.
    ///
    /// Resolution order per reference:
    /// 1. Absolute `<Path>` exists on disk -> not missing.
    /// 2. `<RelativePath>` resolved against the project folder exists -> not missing.
    /// 3. Neither resolves -> missing.
    ///
    /// References whose absolute path lives on an unmounted external volume are
    /// treated as NOT missing — the sample may well exist, the drive is just
    /// offline, and flagging it would be a false alarm.
    ///
    /// Internal (not private) so unit tests can exercise resolution directly.
    nonisolated static func detectMissingSamples(
        references: [SampleFileReference],
        projectFolder: URL
    ) -> Bool {
        guard !references.isEmpty else { return false }

        let fm = FileManager.default
        var existsCache: [String: Bool] = [:] // Dedupes stat calls across references
        var volumeMountedCache: [String: Bool] = [:]

        func fileExists(_ path: String) -> Bool {
            if let cached = existsCache[path] { return cached }
            let exists = fm.fileExists(atPath: path)
            existsCache[path] = exists
            return exists
        }

        /// "/Volumes/X/..." -> "/Volumes/X", nil for non-volume paths
        func volumeRoot(of path: String) -> String? {
            let prefix = "/Volumes/"
            guard path.hasPrefix(prefix) else { return nil }
            guard let volumeName = path.dropFirst(prefix.count).split(separator: "/").first,
                  !volumeName.isEmpty else { return nil }
            return prefix + volumeName
        }

        func isVolumeMounted(_ root: String) -> Bool {
            if let cached = volumeMountedCache[root] { return cached }
            let mounted = fm.fileExists(atPath: root)
            volumeMountedCache[root] = mounted
            return mounted
        }

        // Lazily built index of filenames under the project's own Samples/ tree.
        // Live auto-locates moved samples by name; a sample that exists anywhere
        // in the project folder will open fine even if its recorded paths are stale.
        var samplesFilenameIndex: Set<String>?
        func projectSampleFilenames() -> Set<String> {
            if let samplesFilenameIndex { return samplesFilenameIndex }
            var names: Set<String> = []
            let samplesURL = projectFolder.appendingPathComponent("Samples")
            if let enumerator = fm.enumerator(
                at: samplesURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                var count = 0
                while let url = enumerator.nextObject() as? URL {
                    count += 1
                    if count > 10_000 { break }
                    names.insert(url.lastPathComponent.lowercased())
                }
            }
            samplesFilenameIndex = names
            return names
        }

        for reference in references {
            // Ableton-managed content (factory packs, Core/User Library) is resolved
            // through Live's own browser index — a stale absolute path there says
            // nothing about whether the sample is actually available.
            if [reference.absolutePath, reference.relativePath]
                .compactMap({ $0 })
                .contains(where: Self.isAbletonLibraryContent) {
                continue
            }

            if let absolutePath = reference.absolutePath {
                if let root = volumeRoot(of: absolutePath), !isVolumeMounted(root) {
                    // Volume is offline — can't verify, don't raise a false alarm
                    continue
                }
                if fileExists(absolutePath) {
                    continue
                }
            }

            if let relativePath = reference.relativePath {
                let resolved = projectFolder.appendingPathComponent(relativePath).standardizedFileURL.path
                if fileExists(resolved) {
                    continue
                }
            }

            // Last chance: emulate Live's auto-locate by filename within the project
            if let sourcePath = reference.absolutePath ?? reference.relativePath {
                let filename = URL(fileURLWithPath: sourcePath).lastPathComponent.lowercased()
                if !filename.isEmpty, projectSampleFilenames().contains(filename) {
                    continue
                }
            }

            // Reference carried path info but nothing resolved
            return true
        }

        return false
    }

    /// Path markers for content Live resolves via its own library index.
    private nonisolated static let abletonLibraryMarkers = [
        "/Factory Packs/", "/Core Library/", "/User Library/",
        "/App-Resources/", "/Live Packs/", "/Cloud Library/"
    ]

    nonisolated static func isAbletonLibraryContent(_ path: String) -> Bool {
        abletonLibraryMarkers.contains { path.contains($0) }
    }

    private nonisolated func calculateFileHash(url: URL) -> String? {
        // Use file size + first/last 64KB for fast hashing instead of reading entire file
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attrs[.size] as? UInt64 else { return nil }

        let sampleSize = min(65536, Int(fileSize)) // 64KB or less

        var hasher = Insecure.MD5()

        // Hash file size
        var size = fileSize
        withUnsafeBytes(of: &size) { hasher.update(bufferPointer: $0) }

        // Hash first chunk
        if let firstChunk = try? handle.read(upToCount: sampleSize) {
            hasher.update(data: firstChunk)
        }

        // Hash last chunk if file is large enough
        if fileSize > UInt64(sampleSize * 2) {
            try? handle.seek(toOffset: fileSize - UInt64(sampleSize))
            if let lastChunk = try? handle.read(upToCount: sampleSize) {
                hasher.update(data: lastChunk)
            }
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}
