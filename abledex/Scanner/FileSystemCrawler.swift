//
//  FileSystemCrawler.swift
//  abledex
//
//  Created by Brett Henderson on 12/14/25.
//

import Foundation

nonisolated struct DiscoveredProject: Sendable {
    let folderPath: URL
    let alsFilePath: URL
    let projectName: String
    let sourceVolume: String
    let createdDate: Date
    let modifiedDate: Date
    let fileSize: Int64?
}

// nonisolated: the crawl must be callable from the scanner's background context.
// Under this module's MainActor default isolation, an unannotated type would pin
// the synchronous full-disk enumeration to the main thread.
nonisolated struct FileSystemCrawler: Sendable {

    /// Directory names whose entire subtrees are skipped during crawling.
    /// These never contain a user's main .als files and can hold thousands of entries.
    /// "Samples" is handled separately — it's only Ableton-managed when it sits
    /// inside a project folder; a user-level folder named Samples may hold projects.
    private static let skippedDirectoryNames: Set<String> = [
        "Backup", "Trash", "Ableton Project Info"
    ]

    /// True when `directory` directly contains an .als file — i.e. it is an
    /// Ableton project folder, so its Samples/ subfolder is Ableton-managed.
    private static func isAbletonProjectFolder(_ directory: URL, cache: inout [String: Bool]) -> Bool {
        let key = directory.path
        if let cached = cache[key] { return cached }
        let containsALS = (try? FileManager.default.contentsOfDirectory(atPath: key))?
            .contains { $0.lowercased().hasSuffix(".als") } ?? false
        cache[key] = containsALS
        return containsALS
    }

    /// Crawls `directory` for .als project files, returning the full list.
    /// Prefer `enumerateProjects(in:onDiscover:)` for large trees — it lets the
    /// caller start parsing while the crawl is still running.
    func findProjects(in directory: URL) throws -> [DiscoveredProject] {
        var projects: [DiscoveredProject] = []
        try enumerateProjects(in: directory) { projects.append($0) }
        return projects
    }

    /// Streams discovered .als project files to `onDiscover` as the crawl proceeds.
    /// Throws `CancellationError` if the surrounding task is cancelled mid-crawl.
    func enumerateProjects(in directory: URL, onDiscover: (DiscoveredProject) -> Void) throws {
        let fm = FileManager.default

        guard fm.fileExists(atPath: directory.path) else {
            return
        }

        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .contentModificationDateKey,
            .creationDateKey,
            .fileSizeKey
        ]

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return
        }

        var entryCount = 0
        var projectFolderCache: [String: Bool] = [:]

        while let fileURL = enumerator.nextObject() as? URL {
            entryCount += 1
            // Crawl is synchronous — poll for cancellation periodically
            if entryCount % 100 == 0, Task.isCancelled {
                throw CancellationError()
            }

            let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys)

            // Prune entire subtrees that never contain main project files
            // instead of enumerating and filtering thousands of entries.
            if resourceValues?.isDirectory == true {
                let name = fileURL.lastPathComponent
                if Self.skippedDirectoryNames.contains(name) {
                    enumerator.skipDescendants()
                } else if name == "Samples",
                          Self.isAbletonProjectFolder(fileURL.deletingLastPathComponent(), cache: &projectFolderCache) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard fileURL.pathExtension.lowercased() == "als" else {
                continue
            }

            let folderURL = fileURL.deletingLastPathComponent()
            let modDate = resourceValues?.contentModificationDate ?? Date()
            let createDate = resourceValues?.creationDate ?? modDate

            let volumeName = Self.volumeName(for: folderURL)
            // Use the .als filename as the project name (without extension)
            let projectName = fileURL.deletingPathExtension().lastPathComponent

            onDiscover(DiscoveredProject(
                folderPath: folderURL,
                alsFilePath: fileURL,
                projectName: projectName,
                sourceVolume: volumeName,
                createdDate: createDate,
                modifiedDate: modDate,
                fileSize: resourceValues?.fileSize.map(Int64.init)
            ))
        }
    }

    func findMainALSFile(in projectFolder: URL) -> URL? {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: projectFolder,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return nil
        }

        let alsFiles = contents.filter { $0.pathExtension.lowercased() == "als" }

        if alsFiles.count == 1 {
            return alsFiles.first
        }

        let folderName = projectFolder.lastPathComponent
        if let matching = alsFiles.first(where: {
            $0.deletingPathExtension().lastPathComponent == folderName
        }) {
            return matching
        }

        return alsFiles.max { a, b in
            let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return aDate < bDate
        }
    }

    static func volumeName(for url: URL) -> String {
        let path = url.path

        if path.hasPrefix("/Volumes/") {
            let components = path.dropFirst("/Volumes/".count).split(separator: "/")
            if let volumeName = components.first {
                return String(volumeName)
            }
        }

        if path.hasPrefix("/Users/") {
            return "Macintosh HD"
        }

        if let resourceValues = try? url.resourceValues(forKeys: [.volumeNameKey]),
           let volumeName = resourceValues.volumeName {
            return volumeName
        }

        return "Unknown"
    }

    static func defaultScanLocations() -> [URL] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        let candidates = [
            home.appendingPathComponent("Music/Ableton"),
            home.appendingPathComponent("Music"),
            home.appendingPathComponent("Documents")
        ].filter { fm.fileExists(atPath: $0.path) }

        // Drop any location that is a descendant of another included location.
        // Overlapping roots (e.g. ~/Music/Ableton inside ~/Music) would otherwise
        // discover the same .als files twice and race on insert.
        return candidates.filter { candidate in
            let candidatePath = candidate.standardizedFileURL.path
            return !candidates.contains { other in
                other != candidate &&
                candidatePath.hasPrefix(other.standardizedFileURL.path + "/")
            }
        }
    }
}
