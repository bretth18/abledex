import Foundation

struct DiscoveredProject: Sendable {
    let folderPath: URL
    let alsFilePath: URL
    let projectName: String
    let sourceVolume: String
    let createdDate: Date
    let modifiedDate: Date
}

struct FileSystemCrawler: Sendable {

    func findProjects(in directory: URL) -> [DiscoveredProject] {
        var projects: [DiscoveredProject] = []
        let fm = FileManager.default

        guard fm.fileExists(atPath: directory.path) else {
            return []
        }

        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .contentModificationDateKey,
            .creationDateKey
        ]

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension.lowercased() == "als" else {
                continue
            }

            // Skip backup folders
            let pathComponents = fileURL.pathComponents
            if pathComponents.contains("Backup") || pathComponents.contains("Trash") {
                continue
            }

            let folderURL = fileURL.deletingLastPathComponent()

            // Get file attributes
            let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys)
            let modDate = resourceValues?.contentModificationDate ?? Date()
            let createDate = resourceValues?.creationDate ?? modDate

            let volumeName = Self.volumeName(for: folderURL)
            // Use the .als filename as the project name (without extension)
            let projectName = fileURL.deletingPathExtension().lastPathComponent

            projects.append(DiscoveredProject(
                folderPath: folderURL,
                alsFilePath: fileURL,
                projectName: projectName,
                sourceVolume: volumeName,
                createdDate: createDate,
                modifiedDate: modDate
            ))
        }

        return projects
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
        var locations: [URL] = []
        let home = FileManager.default.homeDirectoryForCurrentUser

        let abletonMusic = home.appendingPathComponent("Music/Ableton")
        if FileManager.default.fileExists(atPath: abletonMusic.path) {
            locations.append(abletonMusic)
        }

        let music = home.appendingPathComponent("Music")
        if FileManager.default.fileExists(atPath: music.path) && !locations.contains(music) {
            locations.append(music)
        }

        let documents = home.appendingPathComponent("Documents")
        if FileManager.default.fileExists(atPath: documents.path) {
            locations.append(documents)
        }

        return locations
    }
}
