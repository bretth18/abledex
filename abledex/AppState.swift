import Foundation
import SwiftUI

@MainActor
@Observable
final class AppState {
    // MARK: - Dependencies

    let database: AppDatabase
    let scanner: ProjectScanner
    private var volumeMonitor: VolumeMonitor?

    // MARK: - State

    var projects: [ProjectRecord] = []
    var locations: [LocationRecord] = []
    var selectedProjectID: UUID?
    var searchQuery: String = ""

    var isScanning: Bool = false
    var scanProgress: ScanProgress?

    // Sorting
    var sortColumn: SortColumn = .modifiedDate
    var sortAscending: Bool = false

    // Filtering
    var selectedFilter: ProjectFilter = .all
    var selectedVolumeFilter: String?

    // MARK: - Computed Properties

    var filteredProjects: [ProjectRecord] {
        var result = projects

        // Apply search filter
        if !searchQuery.isEmpty {
            let query = searchQuery.lowercased()
            result = result.filter { project in
                project.name.lowercased().contains(query) ||
                project.plugins.contains { $0.lowercased().contains(query) }
            }
        }

        // Apply category filter
        switch selectedFilter {
        case .all:
            break
        case .recentlyModified:
            let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            result = result.filter { ($0.modifiedDate ?? $0.filesystemModifiedDate) >= oneWeekAgo }
        case .missingSamples:
            result = result.filter { $0.hasMissingSamples }
        case .highBPM:
            result = result.filter { ($0.bpm ?? 0) >= 140 }
        case .lowBPM:
            result = result.filter { ($0.bpm ?? 999) < 100 }
        }

        // Apply volume filter
        if let volumeFilter = selectedVolumeFilter {
            result = result.filter { $0.sourceVolume == volumeFilter }
        }

        // Apply sorting
        result.sort { a, b in
            let comparison: Bool
            switch sortColumn {
            case .name:
                comparison = a.name.localizedCompare(b.name) == .orderedAscending
            case .bpm:
                comparison = (a.bpm ?? 0) < (b.bpm ?? 0)
            case .createdDate:
                comparison = (a.createdDate ?? a.filesystemModifiedDate) < (b.createdDate ?? b.filesystemModifiedDate)
            case .modifiedDate:
                comparison = (a.modifiedDate ?? a.filesystemModifiedDate) < (b.modifiedDate ?? b.filesystemModifiedDate)
            case .tracks:
                comparison = a.totalTrackCount < b.totalTrackCount
            case .version:
                comparison = (a.abletonVersion ?? "") < (b.abletonVersion ?? "")
            case .duration:
                comparison = (a.duration ?? 0) < (b.duration ?? 0)
            }
            return sortAscending ? comparison : !comparison
        }

        return result
    }

    var selectedProject: ProjectRecord? {
        guard let id = selectedProjectID else { return nil }
        return projects.first { $0.id == id }
    }

    var uniqueVolumes: [String] {
        Array(Set(projects.map { $0.sourceVolume })).sorted()
    }

    var projectCount: Int {
        projects.count
    }

    // MARK: - Initialization

    nonisolated init(database: AppDatabase) {
        self.database = database
        self.scanner = ProjectScanner(database: database)
    }

    // MARK: - Data Loading

    func loadData() async {
        do {
            projects = try await database.fetchAllProjects()
            locations = try await database.fetchAllLocations()

            if locations.isEmpty {
                await initializeDefaultLocations()
            }
        } catch {
            print("Failed to load data: \(error)")
        }
    }

    private func initializeDefaultLocations() async {
        let defaultPaths = FileSystemCrawler.defaultScanLocations()

        for path in defaultPaths {
            let displayName = path.lastPathComponent
            let location = LocationRecord.autoDetected(path: path.path, displayName: displayName)
            do {
                try await database.saveLocation(location)
                locations.append(location)
            } catch {
                print("Failed to save location \(path): \(error)")
            }
        }
    }

    // MARK: - Scanning

    func startScan() async {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = .starting

        do {
            _ = try await scanner.scanAllLocations { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.scanProgress = progress
                }
            }
            await loadData()
        } catch {
            print("Scan failed: \(error)")
            scanProgress = .failed(error)
        }

        isScanning = false
    }

    func addLocation(path: String) async throws {
        let url = URL(fileURLWithPath: path)
        let displayName = url.lastPathComponent
        let location = LocationRecord.userAdded(path: path, displayName: displayName)
        try await database.saveLocation(location)
        locations.append(location)
    }

    func removeLocation(id: UUID) async throws {
        try await database.deleteLocation(id: id)
        locations.removeAll { $0.id == id }
    }

    // MARK: - Volume Monitoring

    func startVolumeMonitoring() {
        volumeMonitor = VolumeMonitor(
            onMount: { [weak self] url, name in
                Task { @MainActor [weak self] in
                    await self?.handleVolumeMounted(url: url, name: name)
                }
            },
            onUnmount: { [weak self] url, name in
                Task { @MainActor [weak self] in
                    self?.handleVolumeUnmounted(url: url, name: name)
                }
            }
        )
        volumeMonitor?.start()
    }

    func stopVolumeMonitoring() {
        volumeMonitor?.stop()
        volumeMonitor = nil
    }

    private func handleVolumeMounted(url: URL, name: String) async {
        let existingLocation = try? await database.fetchLocation(byPath: url.path)

        if existingLocation == nil {
            let location = LocationRecord.autoDetected(path: url.path, displayName: name)
            try? await database.saveLocation(location)
            locations.append(location)
        }

        await startScan()
    }

    private func handleVolumeUnmounted(url: URL, name: String) {
        projects.removeAll { $0.sourceVolume == name }
    }

    // MARK: - Project Actions

    func openProject(_ project: ProjectRecord) {
        let alsURL = URL(fileURLWithPath: project.alsFilePath)
        NSWorkspace.shared.open(alsURL)
    }

    func revealProject(_ project: ProjectRecord) {
        let folderURL = URL(fileURLWithPath: project.folderPath)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
    }

    func deleteProject(_ project: ProjectRecord) async throws {
        try await database.deleteProject(id: project.id)
        projects.removeAll { $0.id == project.id }
        if selectedProjectID == project.id {
            selectedProjectID = nil
        }
    }

    func updateProjectTags(_ project: ProjectRecord, tags: [String]) async throws {
        var updated = project
        updated.userTags = tags
        try await database.saveProject(updated)

        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = updated
        }
    }

    func updateProjectNotes(_ project: ProjectRecord, notes: String) async throws {
        var updated = project
        updated.userNotes = notes
        try await database.saveProject(updated)

        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = updated
        }
    }
}

// MARK: - Supporting Types

enum SortColumn: String, CaseIterable, Sendable {
    case name = "Name"
    case bpm = "BPM"
    case createdDate = "Created"
    case modifiedDate = "Modified"
    case tracks = "Tracks"
    case version = "Version"
    case duration = "Duration"
}

enum ProjectFilter: String, CaseIterable, Sendable {
    case all = "All Projects"
    case recentlyModified = "Recently Modified"
    case missingSamples = "Missing Samples"
    case highBPM = "High BPM (140+)"
    case lowBPM = "Low BPM (<100)"
}
