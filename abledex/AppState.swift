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

    var projects: [ProjectRecord] = [] {
        didSet {
            // Skip if this is the initial load or batch update in progress
            guard !isInitialLoad, !isBatchUpdating else { return }
            recomputeCachedCounts()
            recomputeFilteredProjects()
        }
    }
    private var isInitialLoad = true
    private var isBatchUpdating = false
    var locations: [LocationRecord] = []
    var selectedProjectIDs: Set<UUID> = []
    var searchQuery: String = "" {
        didSet {
            // Debounce search to avoid filtering on every keystroke
            searchDebounceTask?.cancel()
            searchDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                if !Task.isCancelled {
                    recomputeFilteredProjects()
                }
            }
        }
    }

    // MARK: - Cached Data (for sidebar performance)
    private(set) var statusCounts: [CompletionStatus: Int] = [:]
    private(set) var colorLabelCounts: [ColorLabel: Int] = [:]
    private(set) var volumeCounts: [String: Int] = [:]
    private(set) var tagCounts: [String: Int] = [:]
    private(set) var pluginCounts: [String: Int] = [:]
    private(set) var keyCounts: [String: Int] = [:]
    private(set) var folderCounts: [String: Int] = [:]

    // Cached unique values (avoid recomputing on every render)
    private(set) var cachedUniqueVolumes: [String] = []
    private(set) var cachedUniqueTags: [String] = []
    private(set) var cachedUniquePlugins: [String] = []
    private(set) var cachedUniqueKeys: [String] = []
    private(set) var cachedUniqueFolders: [String] = []
    private(set) var cachedFoldersWithMultipleVersions: [String] = []
    private(set) var cachedProjectsByFolder: [String: [ProjectRecord]] = [:]
    private(set) var cachedDuplicateGroups: [DuplicateGroup] = []
    private(set) var cachedDuplicatesCount: Int = 0
    private(set) var cachedDuplicateProjectIDs: Set<UUID> = []  // O(1) lookup for detail view
    private var duplicateDebounceTask: Task<Void, Never>?

    private func recomputeCachedCounts() {
        var newStatusCounts: [CompletionStatus: Int] = [:]
        var newColorLabelCounts: [ColorLabel: Int] = [:]
        var newVolumeCounts: [String: Int] = [:]
        var newTagCounts: [String: Int] = [:]
        var newPluginCounts: [String: Int] = [:]
        var newKeyCounts: [String: Int] = [:]
        var newFolderCounts: [String: Int] = [:]

        for project in projects {
            // Status
            newStatusCounts[project.completionStatus, default: 0] += 1

            // Color label
            newColorLabelCounts[project.colorLabel, default: 0] += 1

            // Volume
            newVolumeCounts[project.sourceVolume, default: 0] += 1

            // Folder
            newFolderCounts[project.projectFolderName, default: 0] += 1

            // Tags
            for tag in project.userTags {
                newTagCounts[tag, default: 0] += 1
            }

            // Plugins
            for plugin in project.plugins {
                newPluginCounts[plugin, default: 0] += 1
            }

            // Keys
            for key in project.musicalKeys {
                newKeyCounts[key, default: 0] += 1
            }
        }

        statusCounts = newStatusCounts
        colorLabelCounts = newColorLabelCounts
        volumeCounts = newVolumeCounts
        tagCounts = newTagCounts
        pluginCounts = newPluginCounts
        keyCounts = newKeyCounts
        folderCounts = newFolderCounts

        // Compute unique sorted arrays from the count dictionaries
        cachedUniqueVolumes = newVolumeCounts.keys.sorted()
        cachedUniqueTags = newTagCounts.keys.sorted()
        cachedUniquePlugins = newPluginCounts.keys.sorted()
        cachedUniqueKeys = newKeyCounts.keys.sorted()
        cachedUniqueFolders = newFolderCounts.keys.sorted()
        cachedFoldersWithMultipleVersions = newFolderCounts.filter { $0.value > 1 }.keys.sorted()
        cachedProjectsByFolder = Dictionary(grouping: projects, by: { $0.projectFolderName })

        // Debounced duplicate detection — avoids re-running O(n²) on every keystroke/edit
        scheduleDuplicateRecomputation()
    }

    private func scheduleDuplicateRecomputation() {
        duplicateDebounceTask?.cancel()
        duplicateDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }

            let projectsSnapshot = self.projects
            let result = await Task.detached(priority: .utility) {
                let groups = DuplicateDetectionService().findDuplicates(in: projectsSnapshot)
                let ids = Set(groups.flatMap { $0.projects.map { $0.id } })
                return (groups, ids)
            }.value

            guard !Task.isCancelled else { return }
            self.cachedDuplicateGroups = result.0
            self.cachedDuplicateProjectIDs = result.1
            self.cachedDuplicatesCount = result.1.count
        }
    }

    var isScanning: Bool = false
    var scanProgress: ScanProgress?

    // Sorting
    var sortColumn: SortColumn = .modifiedDate { didSet { recomputeFilteredProjects() } }
    var sortAscending: Bool = false { didSet { recomputeFilteredProjects() } }

    // Filtering (with didSet to trigger recomputation)
    var selectedFilter: ProjectFilter = .all { didSet { recomputeFilteredProjects() } }
    var selectedVolumeFilter: String? { didSet { recomputeFilteredProjects() } }
    var selectedStatusFilter: CompletionStatus? { didSet { recomputeFilteredProjects() } }
    var selectedColorLabelFilter: ColorLabel? { didSet { recomputeFilteredProjects() } }
    var selectedTagFilter: String? { didSet { recomputeFilteredProjects() } }
    var selectedPluginFilter: String? { didSet { recomputeFilteredProjects() } }
    var selectedKeyFilter: String? { didSet { recomputeFilteredProjects() } }
    var selectedFolderFilter: String? { didSet { recomputeFilteredProjects() } }
    var showFavoritesOnly: Bool = false { didSet { recomputeFilteredProjects() } }
    var showDuplicatesOnly: Bool = false { didSet { recomputeFilteredProjects() } }

    // Cached filtered projects
    private(set) var cachedFilteredProjects: [ProjectRecord] = []
    private var searchDebounceTask: Task<Void, Never>?

    // MARK: - Computed Properties

    var filteredProjects: [ProjectRecord] {
        cachedFilteredProjects
    }

    private func recomputeFilteredProjects() {
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

        // Apply color label filter
        if let colorLabelFilter = selectedColorLabelFilter {
            result = result.filter { $0.colorLabel == colorLabelFilter }
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

        cachedFilteredProjects = result
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
        cachedUniqueVolumes
    }

    var uniqueTags: [String] {
        cachedUniqueTags
    }

    var uniquePlugins: [String] {
        cachedUniquePlugins
    }

    var uniqueKeys: [String] {
        cachedUniqueKeys
    }

    var uniqueFolders: [String] {
        cachedUniqueFolders
    }

    var projectsByFolder: [String: [ProjectRecord]] {
        cachedProjectsByFolder
    }

    func versionsInSameFolder(as project: ProjectRecord) -> [ProjectRecord] {
        (cachedProjectsByFolder[project.projectFolderName] ?? [])
            .sorted { ($0.modifiedDate ?? $0.filesystemModifiedDate) < ($1.modifiedDate ?? $1.filesystemModifiedDate) }
    }

    var duplicateGroups: [DuplicateGroup] {
        cachedDuplicateGroups
    }

    var duplicatesCount: Int {
        cachedDuplicatesCount
    }

    func hasDuplicates(_ project: ProjectRecord) -> Bool {
        cachedDuplicateProjectIDs.contains(project.id)
    }

    func duplicatesOf(_ project: ProjectRecord) -> [ProjectRecord] {
        // Use cached groups for O(1) lookup instead of O(n) scan
        for group in cachedDuplicateGroups {
            if group.projects.contains(where: { $0.id == project.id }) {
                return group.projects.filter { $0.id != project.id }
            }
        }
        return []
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
            // Fetch from database (off main thread via async)
            let fetchedProjects = try await database.fetchAllProjects()
            let fetchedLocations = try await database.fetchAllLocations()

            // Compute caches off main thread
            let caches = await Task.detached(priority: .userInitiated) {
                self.computeCachesOffMainThread(for: fetchedProjects)
            }.value

            // Apply to state (on main thread, but just assignments)
            locations = fetchedLocations
            statusCounts = caches.statusCounts
            colorLabelCounts = caches.colorLabelCounts
            volumeCounts = caches.volumeCounts
            tagCounts = caches.tagCounts
            pluginCounts = caches.pluginCounts
            keyCounts = caches.keyCounts
            folderCounts = caches.folderCounts
            cachedUniqueVolumes = caches.uniqueVolumes
            cachedUniqueTags = caches.uniqueTags
            cachedUniquePlugins = caches.uniquePlugins
            cachedUniqueKeys = caches.uniqueKeys
            cachedUniqueFolders = caches.uniqueFolders
            cachedFoldersWithMultipleVersions = caches.foldersWithMultipleVersions
            cachedProjectsByFolder = caches.projectsByFolder
            cachedFilteredProjects = caches.filteredProjects
            cachedDuplicateGroups = caches.duplicateGroups
            cachedDuplicatesCount = caches.duplicatesCount
            cachedDuplicateProjectIDs = caches.duplicateProjectIDs

            // Set projects (didSet skipped due to isInitialLoad flag)
            projects = fetchedProjects
            isInitialLoad = false

            if locations.isEmpty {
                await initializeDefaultLocations()
            }
        } catch {
            print("Failed to load data: \(error)")
        }
    }

    private struct ComputedCaches: Sendable {
        var statusCounts: [CompletionStatus: Int]
        var colorLabelCounts: [ColorLabel: Int]
        var volumeCounts: [String: Int]
        var tagCounts: [String: Int]
        var pluginCounts: [String: Int]
        var keyCounts: [String: Int]
        var folderCounts: [String: Int]
        var uniqueVolumes: [String]
        var uniqueTags: [String]
        var uniquePlugins: [String]
        var uniqueKeys: [String]
        var uniqueFolders: [String]
        var foldersWithMultipleVersions: [String]
        var projectsByFolder: [String: [ProjectRecord]]
        var filteredProjects: [ProjectRecord]
        var duplicateGroups: [DuplicateGroup]
        var duplicatesCount: Int
        var duplicateProjectIDs: Set<UUID>
    }

    private nonisolated func computeCachesOffMainThread(for projects: [ProjectRecord]) -> ComputedCaches {
        var statusCounts: [CompletionStatus: Int] = [:]
        var colorLabelCounts: [ColorLabel: Int] = [:]
        var volumeCounts: [String: Int] = [:]
        var tagCounts: [String: Int] = [:]
        var pluginCounts: [String: Int] = [:]
        var keyCounts: [String: Int] = [:]
        var folderCounts: [String: Int] = [:]

        for project in projects {
            statusCounts[project.completionStatus, default: 0] += 1
            colorLabelCounts[project.colorLabel, default: 0] += 1
            volumeCounts[project.sourceVolume, default: 0] += 1
            folderCounts[project.projectFolderName, default: 0] += 1
            for tag in project.userTags { tagCounts[tag, default: 0] += 1 }
            for plugin in project.plugins { pluginCounts[plugin, default: 0] += 1 }
            for key in project.musicalKeys { keyCounts[key, default: 0] += 1 }
        }

        // Sort projects by modified date descending (default sort)
        let sortedProjects = projects.sorted {
            ($0.modifiedDate ?? $0.filesystemModifiedDate) > ($1.modifiedDate ?? $1.filesystemModifiedDate)
        }

        // Compute duplicates (O(n²) but done off main thread)
        let duplicateGroups = DuplicateDetectionService().findDuplicates(in: projects)
        let duplicateProjectIDs = Set(duplicateGroups.flatMap { $0.projects.map { $0.id } })

        return ComputedCaches(
            statusCounts: statusCounts,
            colorLabelCounts: colorLabelCounts,
            volumeCounts: volumeCounts,
            tagCounts: tagCounts,
            pluginCounts: pluginCounts,
            keyCounts: keyCounts,
            folderCounts: folderCounts,
            uniqueVolumes: volumeCounts.keys.sorted(),
            uniqueTags: tagCounts.keys.sorted(),
            uniquePlugins: pluginCounts.keys.sorted(),
            uniqueKeys: keyCounts.keys.sorted(),
            uniqueFolders: folderCounts.keys.sorted(),
            foldersWithMultipleVersions: folderCounts.filter { $0.value > 1 }.keys.sorted(),
            projectsByFolder: Dictionary(grouping: projects, by: { $0.projectFolderName }),
            filteredProjects: sortedProjects,
            duplicateGroups: duplicateGroups,
            duplicatesCount: duplicateProjectIDs.count,
            duplicateProjectIDs: duplicateProjectIDs
        )
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

    func startScan(forceReparse: Bool = false) async {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = .starting

        // Run scan in detached task to avoid blocking MainActor
        let scanner = self.scanner
        let result: Result<Int, Error> = await Task.detached(priority: .userInitiated) {
            do {
                let count = try await scanner.scanAllLocations(forceReparse: forceReparse) { progress in
                    Task { @MainActor in
                        // Use weak reference pattern inline
                        await MainActor.run { [weak self] in
                            self?.scanProgress = progress
                        }
                    }
                }
                return .success(count)
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success:
            await loadData()
        case .failure(let error):
            print("Scan failed: \(error)")
            scanProgress = .failed(error)
        }

        isScanning = false
    }

    func startLocationScan(_ location: LocationRecord) async {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = .starting

        let scanner = self.scanner
        let result: Result<Int, Error> = await Task.detached(priority: .userInitiated) {
            do {
                let count = try await scanner.scanLocation(location, forceReparse: true) { progress in
                    Task { @MainActor in
                        await MainActor.run { [weak self] in
                            self?.scanProgress = progress
                        }
                    }
                }
                return .success(count)
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success:
            await loadData()
        case .failure(let error):
            print("Location scan failed: \(error)")
            scanProgress = .failed(error)
        }

        isScanning = false
    }

    func rescanProject(_ project: ProjectRecord) async {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = .parsing(current: 1, total: 1, projectName: project.name)

        let scanner = self.scanner
        let alsPath = project.alsFilePath
        let result: Result<ProjectRecord?, Error> = await Task.detached(priority: .userInitiated) {
            do {
                let record = try await scanner.scanSingleProject(alsFilePath: alsPath)
                return .success(record)
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let record):
            if let record = record, let index = projects.firstIndex(where: { $0.id == record.id }) {
                projects[index] = record
            } else {
                await loadData()
            }
            scanProgress = .completed(projectCount: 1, duration: 0)
        case .failure(let error):
            print("Project rescan failed: \(error)")
            scanProgress = .failed(error)
        }

        isScanning = false
    }

    func rescanProjects(_ projectsToRescan: [ProjectRecord]) async {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = .starting

        let scanner = self.scanner
        let total = projectsToRescan.count

        // Suppress recomputation during the loop, trigger once at end
        isBatchUpdating = true

        var scannedCount = 0
        for project in projectsToRescan {
            scannedCount += 1
            scanProgress = .parsing(current: scannedCount, total: total, projectName: project.name)

            let alsPath = project.alsFilePath
            let result: Result<ProjectRecord?, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    let record = try await scanner.scanSingleProject(alsFilePath: alsPath)
                    return .success(record)
                } catch {
                    return .failure(error)
                }
            }.value

            if case .success(let record) = result,
               let record = record,
               let index = projects.firstIndex(where: { $0.id == record.id }) {
                projects[index] = record
            }
        }

        isBatchUpdating = false
        recomputeCachedCounts()
        recomputeFilteredProjects()

        scanProgress = .completed(projectCount: total, duration: 0)
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

    /// Performs a batch update: collects all mutations, saves to DB in one transaction,
    /// updates the projects array once, then recomputes caches once.
    private func performBatchUpdate(_ mutate: (inout [ProjectRecord]) -> [ProjectRecord]) async throws {
        var mutableProjects = projects
        let updatedRecords = mutate(&mutableProjects)

        guard !updatedRecords.isEmpty else { return }

        // Save all changes in a single DB transaction
        try await database.saveProjects(updatedRecords)

        // Apply to array with recomputation suppressed, then trigger once
        isBatchUpdating = true
        projects = mutableProjects
        isBatchUpdating = false

        recomputeCachedCounts()
        recomputeFilteredProjects()
    }

    func batchSetStatus(_ status: CompletionStatus) async throws {
        try await performBatchUpdate { projects in
            var updated: [ProjectRecord] = []
            for id in selectedProjectIDs {
                if let index = projects.firstIndex(where: { $0.id == id }) {
                    projects[index].completionStatus = status
                    updated.append(projects[index])
                }
            }
            return updated
        }
    }

    func batchAddTag(_ tag: String) async throws {
        try await performBatchUpdate { projects in
            var updated: [ProjectRecord] = []
            for id in selectedProjectIDs {
                if let index = projects.firstIndex(where: { $0.id == id }) {
                    if !projects[index].userTags.contains(tag) {
                        var tags = projects[index].userTags
                        tags.append(tag)
                        projects[index].userTags = tags
                        updated.append(projects[index])
                    }
                }
            }
            return updated
        }
    }

    func batchRemoveTag(_ tag: String) async throws {
        try await performBatchUpdate { projects in
            var updated: [ProjectRecord] = []
            for id in selectedProjectIDs {
                if let index = projects.firstIndex(where: { $0.id == id }) {
                    var tags = projects[index].userTags
                    tags.removeAll { $0 == tag }
                    projects[index].userTags = tags
                    updated.append(projects[index])
                }
            }
            return updated
        }
    }

    func batchToggleFavorite(_ setFavorite: Bool) async throws {
        try await performBatchUpdate { projects in
            var updated: [ProjectRecord] = []
            for id in selectedProjectIDs {
                if let index = projects.firstIndex(where: { $0.id == id }) {
                    projects[index].isFavorite = setFavorite
                    updated.append(projects[index])
                }
            }
            return updated
        }
    }

    func updateProjectColorLabel(_ project: ProjectRecord, colorLabel: ColorLabel) async throws {
        var updated = project
        updated.colorLabel = colorLabel
        try await database.saveProject(updated)

        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = updated
        }
    }

    func batchSetColorLabel(_ colorLabel: ColorLabel) async throws {
        try await performBatchUpdate { projects in
            var updated: [ProjectRecord] = []
            for id in selectedProjectIDs {
                if let index = projects.firstIndex(where: { $0.id == id }) {
                    projects[index].colorLabel = colorLabel
                    updated.append(projects[index])
                }
            }
            return updated
        }
    }

    func colorLabelCount(for label: ColorLabel) -> Int {
        colorLabelCounts[label] ?? 0
    }

    func clearAllFilters() {
        selectedFilter = .all
        selectedVolumeFilter = nil
        selectedStatusFilter = nil
        selectedColorLabelFilter = nil
        selectedTagFilter = nil
        selectedPluginFilter = nil
        selectedKeyFilter = nil
        selectedFolderFilter = nil
        showFavoritesOnly = false
        showDuplicatesOnly = false
        searchQuery = ""
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
