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
    var collections: [CollectionRecord] = []
    var selectedProjectIDs: Set<UUID> = [] {
        didSet {
            // Low-frequency derived flags for the menu bar. Commands must NOT read
            // selectedProjectIDs/projects directly: every mutation would rebuild the
            // main menu, which crashes AppKit's menu impl when it lands mid-tracking
            // (NSRangeException in NSContextMenuImpl). Only write on real transitions.
            let single = selectedProjectIDs.count == 1
            if hasSingleSelection != single { hasSingleSelection = single }
        }
    }
    private(set) var hasSingleSelection = false

    // Volumes that have indexed projects but are not currently mounted.
    // Projects on offline drives stay in the index — tracking them is the app's core purpose.
    private(set) var offlineVolumeNames: Set<String> = []

    // MARK: - Error Surfacing

    struct UserFacingError: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var activeError: UserFacingError?

    func reportError(_ title: String, _ error: Error) {
        activeError = UserFacingError(title: title, message: error.localizedDescription)
    }

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
    private(set) var collectionCounts: [UUID: Int] = [:]
    private(set) var collectionDoneCounts: [UUID: Int] = [:]
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
        var newCollectionCounts: [UUID: Int] = [:]
        var newCollectionDoneCounts: [UUID: Int] = [:]

        for project in projects {
            // Music project membership
            if let collectionID = project.collectionID {
                newCollectionCounts[collectionID, default: 0] += 1
                if project.completionStatus == .done {
                    newCollectionDoneCounts[collectionID, default: 0] += 1
                }
            }
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
        collectionCounts = newCollectionCounts
        collectionDoneCounts = newCollectionDoneCounts

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
            let result = await Self.computeDuplicates(in: projectsSnapshot)

            guard !Task.isCancelled else { return }
            self.cachedDuplicateGroups = result.0
            self.cachedDuplicateProjectIDs = result.1
            self.cachedDuplicatesCount = result.1.count
        }
    }

    @concurrent
    private static func computeDuplicates(in projects: [ProjectRecord]) async -> ([DuplicateGroup], Set<UUID>) {
        let groups = DuplicateDetectionService().findDuplicates(in: projects)
        let ids = Set(groups.flatMap { $0.projects.map(\.id) })
        return (groups, ids)
    }

    // Table implementation toggle for A/B performance comparison (persisted)
    var useNSTableView: Bool = false {
        didSet { UserDefaults.standard.set(useNSTableView, forKey: "useNSTableView") }
    }

    var isScanning: Bool = false
    var scanProgress: ScanProgress?
    private var cancelScanAction: (() -> Void)?

    // Sorting (persisted across launches)
    var sortColumn: SortColumn = .modifiedDate {
        didSet {
            UserDefaults.standard.set(sortColumn.rawValue, forKey: "sortColumn")
            recomputeFilteredProjects()
        }
    }
    var sortAscending: Bool = false {
        didSet {
            UserDefaults.standard.set(sortAscending, forKey: "sortAscending")
            recomputeFilteredProjects()
        }
    }

    // Filtering (with didSet to trigger recomputation)
    var selectedFilter: ProjectFilter = .all { didSet { recomputeFilteredProjects() } }
    var selectedVolumeFilter: String? { didSet { recomputeFilteredProjects() } }
    var selectedStatusFilter: CompletionStatus? { didSet { recomputeFilteredProjects() } }
    var selectedColorLabelFilter: ColorLabel? { didSet { recomputeFilteredProjects() } }
    var selectedTagFilter: String? { didSet { recomputeFilteredProjects() } }
    var selectedPluginFilter: String? { didSet { recomputeFilteredProjects() } }
    var selectedKeyFilter: String? { didSet { recomputeFilteredProjects() } }
    var selectedFolderFilter: String? { didSet { recomputeFilteredProjects() } }
    var selectedCollectionFilter: UUID? { didSet { recomputeFilteredProjects() } }
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
        guard !isBatchUpdating else { return }
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

        // Apply music-project (collection) filter
        if let collectionFilter = selectedCollectionFilter {
            result = result.filter { $0.collectionID == collectionFilter }
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

        // Prune selection to visible rows — otherwise the batch toolbar counts,
        // detail pane, and Delete key keep acting on projects the user can't see.
        let visibleIDs = Set(result.map(\.id))
        if !selectedProjectIDs.isSubset(of: visibleIDs) {
            selectedProjectIDs = selectedProjectIDs.intersection(visibleIDs)
        }
    }

    /// True when any filter or search narrows the visible projects (sort excluded).
    var hasActiveFilters: Bool {
        !searchQuery.isEmpty || selectedFilter != .all || selectedVolumeFilter != nil ||
        selectedStatusFilter != nil || selectedColorLabelFilter != nil || selectedTagFilter != nil ||
        selectedPluginFilter != nil || selectedKeyFilter != nil || selectedFolderFilter != nil ||
        selectedCollectionFilter != nil || showFavoritesOnly || showDuplicatesOnly
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

    init(database: AppDatabase) {
        self.database = database
        self.scanner = ProjectScanner(database: database)
        self.audioPreview = AudioPreviewService()

        // Restore persisted UI state (assignments in init don't trigger didSet)
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "sortColumn"), let column = SortColumn(rawValue: raw) {
            self.sortColumn = column
        }
        self.sortAscending = defaults.bool(forKey: "sortAscending")
        self.useNSTableView = defaults.bool(forKey: "useNSTableView")
    }

    // MARK: - Data Loading

    private var loadTask: Task<Void, Never>?

    func loadData() async {
        // Coalesce overlapping loads: cancel the in-flight one so a slow, stale
        // fetch can't overwrite newer state after a faster reload.
        loadTask?.cancel()
        let task = Task { await performLoad() }
        loadTask = task
        await task.value
    }

    private func performLoad() async {
        do {
            // Fetch from database (off main thread via async)
            let fetchedProjects = try await database.fetchAllProjects()
            let fetchedLocations = try await database.fetchAllLocations()
            let fetchedCollections = try await database.fetchAllCollections()

            // Compute caches off main thread (@concurrent hops to the pool)
            let caches = await Self.computeCaches(for: fetchedProjects)

            guard !Task.isCancelled else { return }

            // Apply to state (on main thread, but just assignments)
            locations = fetchedLocations
            collections = fetchedCollections
            collectionCounts = caches.collectionCounts
            collectionDoneCounts = caches.collectionDoneCounts
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
            offlineVolumeNames = caches.offlineVolumes

            // Set projects with didSet suppressed — the caches above were already
            // computed off the main thread; re-running the didSet recompute here
            // would redo all of it synchronously on the main actor.
            isBatchUpdating = true
            projects = fetchedProjects
            isBatchUpdating = false
            isInitialLoad = false

            // The precomputed filtered list assumes default sort and no filters.
            if hasNonDefaultFilterOrSort {
                recomputeFilteredProjects()
            }

            if locations.isEmpty {
                await initializeDefaultLocations()
            }
        } catch {
            if !Task.isCancelled {
                reportError("Failed to Load Library", error)
            }
        }
    }

    private var hasNonDefaultFilterOrSort: Bool {
        !searchQuery.isEmpty || selectedFilter != .all || selectedVolumeFilter != nil ||
        selectedStatusFilter != nil || selectedColorLabelFilter != nil || selectedTagFilter != nil ||
        selectedPluginFilter != nil || selectedKeyFilter != nil || selectedFolderFilter != nil ||
        selectedCollectionFilter != nil || showFavoritesOnly || showDuplicatesOnly ||
        sortColumn != .modifiedDate || sortAscending
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
        var offlineVolumes: Set<String>
        var collectionCounts: [UUID: Int]
        var collectionDoneCounts: [UUID: Int]
    }

    @concurrent
    private static func computeCaches(for projects: [ProjectRecord]) async -> ComputedCaches {
        var statusCounts: [CompletionStatus: Int] = [:]
        var colorLabelCounts: [ColorLabel: Int] = [:]
        var volumeCounts: [String: Int] = [:]
        var tagCounts: [String: Int] = [:]
        var pluginCounts: [String: Int] = [:]
        var keyCounts: [String: Int] = [:]
        var folderCounts: [String: Int] = [:]

        var volumeSamplePaths: [String: String] = [:]
        var collectionCounts: [UUID: Int] = [:]
        var collectionDoneCounts: [UUID: Int] = [:]

        for project in projects {
            statusCounts[project.completionStatus, default: 0] += 1
            colorLabelCounts[project.colorLabel, default: 0] += 1
            volumeCounts[project.sourceVolume, default: 0] += 1
            folderCounts[project.projectFolderName, default: 0] += 1
            for tag in project.userTags { tagCounts[tag, default: 0] += 1 }
            for plugin in project.plugins { pluginCounts[plugin, default: 0] += 1 }
            for key in project.musicalKeys { keyCounts[key, default: 0] += 1 }
            if volumeSamplePaths[project.sourceVolume] == nil {
                volumeSamplePaths[project.sourceVolume] = project.alsFilePath
            }
            if let collectionID = project.collectionID {
                collectionCounts[collectionID, default: 0] += 1
                if project.completionStatus == .done {
                    collectionDoneCounts[collectionID, default: 0] += 1
                }
            }
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
            duplicateProjectIDs: duplicateProjectIDs,
            offlineVolumes: Self.offlineVolumes(volumeSamplePaths: volumeSamplePaths),
            collectionCounts: collectionCounts,
            collectionDoneCounts: collectionDoneCounts
        )
    }

    /// External volumes are indexed by their `/Volumes/<name>` component, so a missing
    /// mount point usually means the drive is unplugged — but volumes can also be
    /// mounted elsewhere (network shares, secondary APFS volumes), so an existing
    /// project file always proves the volume is reachable. The boot volume never counts.
    private nonisolated static func offlineVolumes(volumeSamplePaths: [String: String]) -> Set<String> {
        var offline: Set<String> = []
        let fm = FileManager.default
        for (name, samplePath) in volumeSamplePaths where name != "Macintosh HD" && name != "Unknown" {
            if fm.fileExists(atPath: "/Volumes/\(name)") { continue }
            if fm.fileExists(atPath: samplePath) { continue }
            offline.insert(name)
        }
        return offline
    }

    func isVolumeOnline(_ project: ProjectRecord) -> Bool {
        !offlineVolumeNames.contains(project.sourceVolume)
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
        await runScan { scanner, progress in
            try await scanner.scanAllLocations(forceReparse: forceReparse, progress: progress)
        }
    }

    func startLocationScan(_ location: LocationRecord) async {
        await runScan { scanner, progress in
            try await scanner.scanLocation(location, forceReparse: true, progress: progress)
        }
    }

    /// Shared scan driver. The scanner's entry points are @concurrent, so awaiting
    /// them from the main actor runs the crawl/parse work on the concurrent pool;
    /// the wrapping Task exists only to give Stop Scan a handle to cancel.
    private func runScan(
        _ operation: @escaping @Sendable (ProjectScanner, @escaping @Sendable (ScanProgress) -> Void) async throws -> Int
    ) async {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = .starting

        let scanner = self.scanner
        let task = Task { () -> Result<Int, Error> in
            do {
                let count = try await operation(scanner) { [weak self] progress in
                    Task { @MainActor in
                        self?.scanProgress = progress
                    }
                }
                return .success(count)
            } catch {
                return .failure(error)
            }
        }
        cancelScanAction = { task.cancel() }
        let result = await task.value
        cancelScanAction = nil

        await finishScan(with: result)
    }

    func cancelScan() {
        cancelScanAction?()
    }

    private func finishScan(with result: Result<Int, Error>) async {
        switch result {
        case .success:
            await loadData()
        case .failure(let error):
            if error is CancellationError {
                // Batches saved before cancellation are already in the DB — show them.
                scanProgress = nil
                await loadData()
            } else {
                reportError("Scan Failed", error)
                scanProgress = .failed(error)
            }
        }

        isScanning = false
    }

    func rescanProject(_ project: ProjectRecord) async {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = .parsing(current: 1, total: 1, projectName: project.name)

        let scanner = self.scanner
        let alsPath = project.alsFilePath
        let task = Task { () -> Result<ProjectRecord?, Error> in
            do {
                let record = try await scanner.scanSingleProject(alsFilePath: alsPath)
                return .success(record)
            } catch {
                return .failure(error)
            }
        }
        cancelScanAction = { task.cancel() }
        let result = await task.value
        cancelScanAction = nil

        switch result {
        case .success(let record):
            if let record = record, projects.contains(where: { $0.id == record.id }) {
                applyUpdatedProject(record)
            } else {
                await loadData()
            }
            scanProgress = .completed(projectCount: 1, duration: 0)
        case .failure(let error):
            reportError("Rescan Failed", error)
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

        var isCancelled = false
        cancelScanAction = { isCancelled = true }

        // Collect results first; state is applied in one synchronous pass below so
        // filter/search changes made mid-rescan aren't swallowed by isBatchUpdating.
        var updatedRecords: [ProjectRecord] = []
        var scannedCount = 0
        for project in projectsToRescan {
            if isCancelled { break }
            scannedCount += 1
            scanProgress = .parsing(current: scannedCount, total: total, projectName: project.name)

            // scanSingleProject is @concurrent — parsing runs off the main actor.
            if let record = try? await scanner.scanSingleProject(alsFilePath: project.alsFilePath) {
                updatedRecords.append(record)
            }
        }
        cancelScanAction = nil

        // Apply all updates in one pass with no suspension points
        let indexByID = Dictionary(uniqueKeysWithValues: projects.enumerated().map { ($1.id, $0) })
        isBatchUpdating = true
        for record in updatedRecords {
            if let index = indexByID[record.id] {
                projects[index] = record
            }
        }
        isBatchUpdating = false
        recomputeCachedCounts()
        recomputeFilteredProjects()

        scanProgress = isCancelled ? nil : .completed(projectCount: updatedRecords.count, duration: 0)
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
        // Idempotent: the WindowGroup .task re-runs on every window open, and the
        // old monitor's DA callbacks hold an unretained pointer to it.
        guard volumeMonitor == nil else { return }
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

        // DiskArbitration doesn't reliably report Finder ejects (volume unmounted,
        // device still attached) — the NSWorkspace notifications do.
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didMountNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            let name = (note.userInfo?[NSWorkspace.localizedVolumeNameUserInfoKey] as? String) ?? url.lastPathComponent
            Task { @MainActor [weak self] in
                await self?.handleVolumeMounted(url: url, name: name)
            }
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            let name = (note.userInfo?[NSWorkspace.localizedVolumeNameUserInfoKey] as? String) ?? url.lastPathComponent
            Task { @MainActor [weak self] in
                self?.handleVolumeUnmounted(url: url, name: name)
            }
        })
    }

    private var workspaceObservers: [NSObjectProtocol] = []

    func stopVolumeMonitoring() {
        volumeMonitor?.stop()
        volumeMonitor = nil
        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            center.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    private var mountsBeingHandled: Set<String> = []

    private func handleVolumeMounted(url: URL, name: String) async {
        offlineVolumeNames.remove(name)

        // Respect the "Scan external volumes automatically" setting
        guard UserDefaults.standard.object(forKey: "scanExternalVolumes") as? Bool ?? true else { return }

        // A single physical mount fires both DiskArbitration and NSWorkspace
        // notifications — without this guard both race saveLocation into a
        // UNIQUE(path) violation and the user gets a spurious error alert.
        guard !mountsBeingHandled.contains(url.path) else { return }
        mountsBeingHandled.insert(url.path)
        defer { mountsBeingHandled.remove(url.path) }

        let existingLocation = try? await database.fetchLocation(byPath: url.path)

        if existingLocation == nil {
            let location = LocationRecord.autoDetected(path: url.path, displayName: name)
            do {
                try await database.saveLocation(location)
                locations.append(location)
            } catch {
                reportError("Failed to Add Location", error)
            }
        }

        await startScan()
    }

    private func handleVolumeUnmounted(url: URL, name: String) {
        // Keep the projects indexed — remembering what lives on unplugged drives
        // is the app's core purpose. Just mark the volume offline.
        if volumeCounts.keys.contains(name) {
            offlineVolumeNames.insert(name)
        }
    }

    // MARK: - Incremental Updates

    /// Applies a single-record change without re-aggregating the whole library.
    /// The `projects` didSet path (full recount + O(n²) duplicate rescheduling)
    /// is far too expensive for one favorite/status/tag click on a big library.
    private func applyUpdatedProject(_ updated: ProjectRecord) {
        guard let index = projects.firstIndex(where: { $0.id == updated.id }) else { return }
        let old = projects[index]

        isBatchUpdating = true
        projects[index] = updated
        isBatchUpdating = false

        applyCacheDelta(old: old, new: updated)
        recomputeFilteredProjects()

        // Duplicate detection only depends on hash/BPM/plugins — skip the O(n²)
        // reschedule for pure metadata edits.
        if old.fileHash != updated.fileHash || old.bpm != updated.bpm || old.pluginsJSON != updated.pluginsJSON {
            scheduleDuplicateRecomputation()
        }
    }

    private func applyCacheDelta(old: ProjectRecord, new: ProjectRecord) {
        if old.completionStatus != new.completionStatus {
            adjust(&statusCounts, remove: old.completionStatus, add: new.completionStatus)
        }
        if old.colorLabel != new.colorLabel {
            adjust(&colorLabelCounts, remove: old.colorLabel, add: new.colorLabel)
        }
        if old.sourceVolume != new.sourceVolume {
            adjust(&volumeCounts, remove: old.sourceVolume, add: new.sourceVolume)
            cachedUniqueVolumes = volumeCounts.keys.sorted()
        }

        let oldTags = Set(old.userTags), newTags = Set(new.userTags)
        if oldTags != newTags {
            for tag in oldTags.subtracting(newTags) { adjust(&tagCounts, remove: tag, add: nil) }
            for tag in newTags.subtracting(oldTags) { adjust(&tagCounts, remove: nil, add: tag) }
            cachedUniqueTags = tagCounts.keys.sorted()
        }

        let oldPlugins = Set(old.plugins), newPlugins = Set(new.plugins)
        if oldPlugins != newPlugins {
            for plugin in oldPlugins.subtracting(newPlugins) { adjust(&pluginCounts, remove: plugin, add: nil) }
            for plugin in newPlugins.subtracting(oldPlugins) { adjust(&pluginCounts, remove: nil, add: plugin) }
            cachedUniquePlugins = pluginCounts.keys.sorted()
        }

        let oldKeys = Set(old.musicalKeys), newKeys = Set(new.musicalKeys)
        if oldKeys != newKeys {
            for key in oldKeys.subtracting(newKeys) { adjust(&keyCounts, remove: key, add: nil) }
            for key in newKeys.subtracting(oldKeys) { adjust(&keyCounts, remove: nil, add: key) }
            cachedUniqueKeys = keyCounts.keys.sorted()
        }

        // Music-project membership / done-progress deltas
        if old.collectionID != new.collectionID || old.completionStatus != new.completionStatus {
            if let oldID = old.collectionID {
                adjust(&collectionCounts, remove: oldID, add: nil)
                if old.completionStatus == .done { adjust(&collectionDoneCounts, remove: oldID, add: nil) }
            }
            if let newID = new.collectionID {
                adjust(&collectionCounts, remove: nil, add: newID)
                if new.completionStatus == .done { adjust(&collectionDoneCounts, remove: nil, add: newID) }
            }
        }

        // Folder name only changes on rescan/move — fall back to the full pass then.
        if old.projectFolderName != new.projectFolderName {
            recomputeCachedCounts()
            return
        }

        // Keep the record fresh inside its folder group (version timeline reads it)
        if var group = cachedProjectsByFolder[new.projectFolderName],
           let groupIndex = group.firstIndex(where: { $0.id == new.id }) {
            group[groupIndex] = new
            cachedProjectsByFolder[new.projectFolderName] = group
        }
    }

    private func adjust<Key: Hashable>(_ counts: inout [Key: Int], remove oldKey: Key?, add newKey: Key?) {
        if let oldKey {
            let count = (counts[oldKey] ?? 1) - 1
            if count <= 0 { counts.removeValue(forKey: oldKey) } else { counts[oldKey] = count }
        }
        if let newKey {
            counts[newKey, default: 0] += 1
        }
    }

    // MARK: - Project Actions

    func openProject(_ project: ProjectRecord) {
        // Judge reachability by the file itself, not the offline flag — volumes
        // mounted outside /Volumes (network shares, secondary APFS volumes) are
        // reachable even when no /Volumes/<name> mount point exists.
        guard FileManager.default.fileExists(atPath: project.alsFilePath) else {
            let message = isVolumeOnline(project)
                ? "\"\(project.name)\" could not be found at \(project.alsFilePath). It may have been moved or deleted — try re-scanning."
                : "\"\(project.name)\" is on \"\(project.sourceVolume)\", which isn't currently mounted. Connect the drive and try again."
            activeError = UserFacingError(title: "Project Not Available", message: message)
            return
        }

        let alsURL = URL(fileURLWithPath: project.alsFilePath)
        let projectID = project.id

        Task {
            do {
                // Async variant — the sync open() can block the main actor while Live launches
                try await NSWorkspace.shared.open(alsURL, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                reportError("Failed to Open Project", error)
                return
            }

            // Track last opened time on the CURRENT record — Live can take many
            // seconds to launch, and saving the click-time snapshot would revert
            // any edits the user made in the meantime.
            guard let current = projects.first(where: { $0.id == projectID }) else { return }
            var updated = current
            updated.lastOpenedAt = Date()
            try? await database.saveProject(updated)
            applyUpdatedProject(updated)
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
        applyUpdatedProject(updated)
    }

    func updateProjectNotes(_ project: ProjectRecord, notes: String) async throws {
        var updated = project
        updated.userNotes = notes
        try await database.saveProject(updated)
        applyUpdatedProject(updated)
    }

    func updateProjectStatus(_ project: ProjectRecord, status: CompletionStatus) async throws {
        var updated = project
        updated.completionStatus = status
        try await database.saveProject(updated)
        applyUpdatedProject(updated)
    }

    func toggleFavorite(_ project: ProjectRecord) async throws {
        var updated = project
        updated.isFavorite = !project.isFavorite
        try await database.saveProject(updated)
        applyUpdatedProject(updated)
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
        applyUpdatedProject(updated)
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

    // MARK: - Music Projects (Collections)

    @discardableResult
    func createCollection(name: String, kind: CollectionKind) async throws -> CollectionRecord {
        let collection = CollectionRecord.new(name: name, kind: kind)
        try await database.saveCollection(collection)
        collections.append(collection)
        sortCollections()
        return collection
    }

    func updateCollection(_ collection: CollectionRecord) async throws {
        // Optimistic: apply in memory first so pickers don't visibly snap back
        // while the save is in flight; the error alert covers the failure case.
        if let index = collections.firstIndex(where: { $0.id == collection.id }) {
            collections[index] = collection
        }
        sortCollections()
        try await database.saveCollection(collection)
    }

    func deleteCollection(_ collection: CollectionRecord) async throws {
        try await database.deleteCollection(id: collection.id)
        collections.removeAll { $0.id == collection.id }
        if selectedCollectionFilter == collection.id {
            selectedCollectionFilter = nil
        }

        // Clear membership in memory (DB rows were cleared in the same transaction)
        isBatchUpdating = true
        for index in projects.indices where projects[index].collectionID == collection.id {
            projects[index].collectionID = nil
        }
        isBatchUpdating = false
        collectionCounts[collection.id] = nil
        collectionDoneCounts[collection.id] = nil
        recomputeFilteredProjects()
    }

    /// Assigns (or with nil, removes) the given projects to a music project.
    func assignProjects(_ projectIDs: Set<UUID>, toCollection collectionID: UUID?) async throws {
        guard !projectIDs.isEmpty else { return }
        try await database.assignProjects(ids: Array(projectIDs), toCollection: collectionID)

        isBatchUpdating = true
        for index in projects.indices where projectIDs.contains(projects[index].id) {
            projects[index].collectionID = collectionID
        }
        isBatchUpdating = false
        recomputeCachedCounts()
        recomputeFilteredProjects()
    }

    func collection(for project: ProjectRecord) -> CollectionRecord? {
        guard let id = project.collectionID else { return nil }
        return collections.first { $0.id == id }
    }

    /// Progress of a music project: how many member tracks are Done out of the total.
    func collectionProgress(_ collection: CollectionRecord) -> (done: Int, total: Int) {
        (collectionDoneCounts[collection.id] ?? 0, collectionCounts[collection.id] ?? 0)
    }

    private func sortCollections() {
        collections.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// Toggles a sidebar section filter (status/tag/plugin/...), resetting the
    /// Library filter so two highlighted rows don't silently AND into an empty
    /// table. Batched into a single recompute.
    func toggleSectionFilter<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<AppState, T?>, _ value: T) {
        isBatchUpdating = true
        if selectedFilter != .all {
            selectedFilter = .all
        }
        if self[keyPath: keyPath] == value {
            self[keyPath: keyPath] = nil
        } else {
            self[keyPath: keyPath] = value
        }
        isBatchUpdating = false
        recomputeFilteredProjects()
    }

    func clearAllFilters() {
        // Suppress recomputation during batch reset, trigger once at end
        isBatchUpdating = true
        selectedFilter = .all
        selectedVolumeFilter = nil
        selectedStatusFilter = nil
        selectedColorLabelFilter = nil
        selectedTagFilter = nil
        selectedPluginFilter = nil
        selectedKeyFilter = nil
        selectedFolderFilter = nil
        selectedCollectionFilter = nil
        showFavoritesOnly = false
        showDuplicatesOnly = false
        searchQuery = ""
        isBatchUpdating = false
        recomputeFilteredProjects()
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
