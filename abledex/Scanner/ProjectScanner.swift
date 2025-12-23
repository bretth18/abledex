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
}

final class ProjectScanner: Sendable {
    private let database: AppDatabase
    private let crawler = FileSystemCrawler()

    nonisolated init(database: AppDatabase) {
        self.database = database
    }

    func scanAllLocations(
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> Int {
        let startTime = Date()
        progress(.starting)

        let locations = try await database.fetchEnabledLocations()
        var totalProjects = 0

        for location in locations {
            let count = try await scanLocation(location, progress: progress)
            totalProjects += count
        }

        let duration = Date().timeIntervalSince(startTime)
        progress(.completed(projectCount: totalProjects, duration: duration))

        return totalProjects
    }

    func scanLocation(
        _ location: LocationRecord,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> Int {
        let locationURL = URL(fileURLWithPath: location.path)

        progress(.discovering(location: location.displayName))

        // Discovery happens synchronously but is fast
        let discoveredProjects = crawler.findProjects(in: locationURL)
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
        let batchSize = 10

        for batch in stride(from: 0, to: total, by: batchSize) {
            let end = min(batch + batchSize, total)
            let batchProjects = Array(discoveredProjects[batch..<end])

            // Parse batch concurrently
            let records = await withTaskGroup(of: ProjectRecord?.self) { group in
                for discovered in batchProjects {
                    let existing = existingProjects[discovered.alsFilePath.path]
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

            // Save batch to database
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
                abletonMinorVersion: nil,
                duration: parsedData.duration,
                samplePathsJSON: samplePathsJSON,
                pluginsJSON: pluginsJSON,
                musicalKeysJSON: musicalKeysJSON,
                hasMissingSamples: false, // Don't check - too slow and unreliable
                fileHash: fileHash,
                lastIndexedAt: Date(),
                userTagsJSON: existing?.userTagsJSON,
                userNotes: existing?.userNotes,
                completionStatus: existing?.completionStatus ?? .none,
                colorLabel: existing?.colorLabel ?? .none,
                isFavorite: existing?.isFavorite ?? false,
                lastOpenedAt: existing?.lastOpenedAt
            )
        } catch {
            print("Failed to parse \(discovered.projectName): \(error.localizedDescription)")
            return nil
        }
    }

    private nonisolated func calculateFileHash(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}
