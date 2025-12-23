//
//  AppState.swift
//  abledex
//
//  Created by Brett Henderson on 12/14/25.
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class AppState {
    // MARK: - Dependencies

    let database: AppDatabase
    let scanner: ProjectScanner
    let audioPreview: AudioPreviewService
    let duplicateService = DuplicateDetectionService()
    private var volumeMonitor: VolumeMonitor?

    // MARK: - State

    var projects: [ProjectRecord] = []
    var locations: [LocationRecord] = []
    var selectedProjectIDs: Set<UUID> = []
    var searchQuery: String = ""

    var isScanning: Bool = false
    var scanProgress: ScanProgress?

    // Sorting
    var sortColumn: SortColumn = .modifiedDate
    var sortAscending: Bool = false

    // Filtering
    var selectedFilter: ProjectFilter = .all
    var selectedVolumeFilter: String?
    var selectedStatusFilter: CompletionStatus?
    var selectedTagFilter: String?
    var selectedPluginFilter: String?
    var selectedKeyFilter: String?
    var selectedFolderFilter: String?
    var showFavoritesOnly: Bool = false
    var showDuplicatesOnly: Bool = false

    // MARK: - Computed Properties

    var filteredProjects: [ProjectRecord] {
        var result = projects

        // Apply search filter (includes name, plugins, and tags)
        if !searchQuery.isEmpty {
            let query = searchQuery.lowercased()
            result = result.filter { project in
                project.name.lowercased().contains(query) ||
                project.plugins.contains { $0.lowercased().contains(query) } ||
                project.userTags.contains { $0.lowercased().contains(query) }
            }
        }

        // Apply category filter
        switch selectedFilter {
        case .all:
            break
        case .favorites:
            result = result.filter { $0.isFavorite }
        case .recentlyOpened:
            let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            result = result.filter { ($0.lastOpenedAt ?? .distantPast) >= oneWeekAgo }
        case .recentlyModified:
            let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            result = result.filter { ($0.modifiedDate ?? $0.filesystemModifiedDate) >= oneWeekAgo }
        case .missingSamples:
            result = result.filter { $0.hasMissingSamples }
        case .highBPM:
            result = result.filter { ($0.bpm ?? 0) >= 130 }
        case .normalBPM:
            result = result.filter { ($0.bpm ?? 0) >= 100 && ($0.bpm ?? 0) < 130 }
        case .lowBPM:
            result = result.filter { ($0.bpm ?? 999) < 100 }
        }

        // Apply volume filter
        if let volumeFilter = selectedVolumeFilter {
            result = result.filter { $0.sourceVolume == volumeFilter }
        }

        // Apply status filter
        if let statusFilter = selectedStatusFilter {
            result = result.filter { $0.completionStatus == statusFilter }
        }

        // Apply tag filter
        if let tagFilter = selectedTagFilter {
            result = result.filter { $0.userTags.contains(tagFilter) }
        }

        // Apply plugin filter
        if let pluginFilter = selectedPluginFilter {
            result = result.filter { $0.plugins.contains(pluginFilter) }
        }

        // Apply key filter
        if let keyFilter = selectedKeyFilter {
            result = result.filter { $0.musicalKeys.contains(keyFilter) }
        }

        // Apply folder filter
        if let folderFilter = selectedFolderFilter {
            result = result.filter { $0.projectFolderName == folderFilter }
        }

        // Apply favorites filter
        if showFavoritesOnly {
            result = result.filter { $0.isFavorite }
        }

        // Apply duplicates filter
        if showDuplicatesOnly {
            let projectsWithDuplicates = Set(duplicateGroups.flatMap { $0.projects.map { $0.id } })
            result = result.filter { projectsWithDuplicates.contains($0.id) }
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
            case .status:
                comparison = a.completionStatus.rawValue < b.completionStatus.rawValue
            case .lastOpened:
                comparison = (a.lastOpenedAt ?? .distantPast) < (b.lastOpenedAt ?? .distantPast)
            }
            return sortAscending ? comparison : !comparison
        }

        return result
    }

    var selectedProject: ProjectRecord? {
        guard selectedProjectIDs.count == 1,
              let id = selectedProjectIDs.first else { return nil }
        return projects.first { $0.id == id }
    }

    var selectedProjects: [ProjectRecord] {
        projects.filter { selectedProjectIDs.contains($0.id) }
    }

    var uniqueVolumes: [String] {
        Array(Set(projects.map { $0.sourceVolume })).sorted()
    }

    var uniqueTags: [String] {
        Array(Set(projects.flatMap { $0.userTags })).sorted()
    }

    var uniquePlugins: [String] {
        Array(Set(projects.flatMap { $0.plugins })).sorted()
    }

    var uniqueKeys: [String] {
        Array(Set(projects.flatMap { $0.musicalKeys })).sorted()
    }

    var uniqueFolders: [String] {
        Array(Set(projects.map { $0.projectFolderName })).sorted()
    }

    var projectsByFolder: [String: [ProjectRecord]] {
        Dictionary(grouping: projects, by: { $0.projectFolderName })
    }

    func versionsInSameFolder(as project: ProjectRecord) -> [ProjectRecord] {
        projects.filter { $0.folderPath == project.folderPath }
            .sorted { ($0.modifiedDate ?? $0.filesystemModifiedDate) < ($1.modifiedDate ?? $1.filesystemModifiedDate) }
    }

    var duplicateGroups: [DuplicateGroup] {
        duplicateService.findDuplicates(in: projects)
    }

    var duplicatesCount: Int {
        Set(duplicateGroups.flatMap { $0.projects.map { $0.id } }).count
    }

    func hasDuplicates(_ project: ProjectRecord) -> Bool {
        duplicateService.hasDuplicates(project, in: projects)
    }

    func duplicatesOf(_ project: ProjectRecord) -> [ProjectRecord] {
        duplicateService.duplicatesOf(project, in: projects)
    }

    var projectCount: Int {
        projects.count
    }

    var favoritesCount: Int {
        projects.filter { $0.isFavorite }.count
    }

    var recentlyOpenedProjects: [ProjectRecord] {
        projects
            .filter { $0.lastOpenedAt != nil }
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
    }

    // MARK: - Initialization

    nonisolated init(database: AppDatabase) {
        self.database = database
        self.scanner = ProjectScanner(database: database)
        self.audioPreview = AudioPreviewService()
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

        // Track last opened time
        Task {
            var updated = project
            updated.lastOpenedAt = Date()
            try? await database.saveProject(updated)
            if let index = projects.firstIndex(where: { $0.id == project.id }) {
                projects[index] = updated
            }
        }
    }

    func revealProject(_ project: ProjectRecord) {
        let folderURL = URL(fileURLWithPath: project.folderPath)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
    }

    func deleteProject(_ project: ProjectRecord) async throws {
        try await database.deleteProject(id: project.id)
        projects.removeAll { $0.id == project.id }
        selectedProjectIDs.remove(project.id)
    }

    func deleteSelectedProjects() async throws {
        let idsToDelete = selectedProjectIDs
        try await database.deleteProjects(ids: Array(idsToDelete))
        projects.removeAll { idsToDelete.contains($0.id) }
        selectedProjectIDs.removeAll()
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

    func updateProjectStatus(_ project: ProjectRecord, status: CompletionStatus) async throws {
        var updated = project
        updated.completionStatus = status
        try await database.saveProject(updated)

        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = updated
        }
    }

    func toggleFavorite(_ project: ProjectRecord) async throws {
        var updated = project
        updated.isFavorite = !project.isFavorite
        try await database.saveProject(updated)

        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = updated
        }
    }

    // MARK: - Batch Operations

    func batchSetStatus(_ status: CompletionStatus) async throws {
        for id in selectedProjectIDs {
            if var project = projects.first(where: { $0.id == id }) {
                project.completionStatus = status
                try await database.saveProject(project)
                if let index = projects.firstIndex(where: { $0.id == id }) {
                    projects[index] = project
                }
            }
        }
    }

    func batchAddTag(_ tag: String) async throws {
        for id in selectedProjectIDs {
            if var project = projects.first(where: { $0.id == id }) {
                if !project.userTags.contains(tag) {
                    var tags = project.userTags
                    tags.append(tag)
                    project.userTags = tags
                    try await database.saveProject(project)
                    if let index = projects.firstIndex(where: { $0.id == id }) {
                        projects[index] = project
                    }
                }
            }
        }
    }

    func batchRemoveTag(_ tag: String) async throws {
        for id in selectedProjectIDs {
            if var project = projects.first(where: { $0.id == id }) {
                var tags = project.userTags
                tags.removeAll { $0 == tag }
                project.userTags = tags
                try await database.saveProject(project)
                if let index = projects.firstIndex(where: { $0.id == id }) {
                    projects[index] = project
                }
            }
        }
    }

    func batchToggleFavorite(_ setFavorite: Bool) async throws {
        for id in selectedProjectIDs {
            if var project = projects.first(where: { $0.id == id }) {
                project.isFavorite = setFavorite
                try await database.saveProject(project)
                if let index = projects.firstIndex(where: { $0.id == id }) {
                    projects[index] = project
                }
            }
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
    case status = "Status"
    case lastOpened = "Last Opened"
}

enum ProjectFilter: String, CaseIterable, Sendable {
    case all = "All Projects"
    case favorites = "Favorites"
    case recentlyOpened = "Recently Opened"
    case recentlyModified = "Recently Modified"
    case missingSamples = "Missing Samples"
    case highBPM = "High BPM (130+)"
    case normalBPM = "Normal BPM (100-130)"
    case lowBPM = "Low BPM (<100)"
}
