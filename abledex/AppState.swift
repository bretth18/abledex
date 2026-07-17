//
//  AppState.swift
//  abledex
//
//  Created by Brett Henderson on 12/14/25.
//

import Foundation
import SwiftUI
import CoreServices
import GRDB
import os

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
            // Any in-memory mutation invalidates observation emissions computed
            // against the previous state (a fresher emission always follows a write).
            projectsMutationGeneration &+= 1
            // Skip if this is the initial load or batch update in progress
            guard !isInitialLoad, !isBatchUpdating else { return }
            recomputeCachedCounts()
            recomputeFilteredProjects()
        }
    }
    private var isInitialLoad = true
    private var isBatchUpdating = false
    private var projectsMutationGeneration = 0
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
            // Debounce, then resolve matches via the FTS5 index off the main
            // actor — substring-scanning every record per keystroke doesn't
            // scale to libraries with thousands of projects.
            searchDebounceTask?.cancel()
            searchDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                if !Task.isCancelled {
                    await resolveSearchMatches()
                }
            }
        }
    }

    /// Project IDs matching the current search per the FTS index; nil when no
    /// FTS result applies (empty query, or query FTS can't tokenize — the
    /// filter falls back to in-memory substring matching then).
    private var searchMatchIDs: Set<UUID>?

    private func resolveSearchMatches() async {
        let query = searchQuery
        guard !query.isEmpty else {
            searchMatchIDs = nil
            recomputeFilteredProjects()
            return
        }
        let matches = (try? await database.searchProjectIDs(matching: query)) ?? nil
        guard query == searchQuery else { return } // superseded by newer keystrokes
        searchMatchIDs = matches
        recomputeFilteredProjects()
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

    /// Everything the filter/sort pass reads, snapshotted so it can run off
    /// the main actor. Filtering + localized sorting of a many-thousand-project
    /// library takes tens of milliseconds — too slow to run on the main thread
    /// for every filter click or keystroke.
    private struct FilterSnapshot: Sendable {
        var projects: [ProjectRecord]
        var searchQuery: String
        var searchMatchIDs: Set<UUID>?
        var selectedFilter: ProjectFilter
        var selectedVolumeFilter: String?
        var selectedStatusFilter: CompletionStatus?
        var selectedColorLabelFilter: ColorLabel?
        var selectedTagFilter: String?
        var selectedPluginFilter: String?
        var selectedKeyFilter: String?
        var selectedFolderFilter: String?
        var selectedCollectionFilter: UUID?
        var showFavoritesOnly: Bool
        var showDuplicatesOnly: Bool
        var duplicateProjectIDs: Set<UUID>
        var sortColumn: SortColumn
        var sortAscending: Bool
    }

    private var filterGeneration = 0
    private var filterRecomputeTask: Task<Void, Never>?

    private func recomputeFilteredProjects() {
        guard !isBatchUpdating else { return }
        filterGeneration &+= 1
        let generation = filterGeneration
        let snapshot = FilterSnapshot(
            projects: projects,
            searchQuery: searchQuery,
            searchMatchIDs: searchMatchIDs,
            selectedFilter: selectedFilter,
            selectedVolumeFilter: selectedVolumeFilter,
            selectedStatusFilter: selectedStatusFilter,
            selectedColorLabelFilter: selectedColorLabelFilter,
            selectedTagFilter: selectedTagFilter,
            selectedPluginFilter: selectedPluginFilter,
            selectedKeyFilter: selectedKeyFilter,
            selectedFolderFilter: selectedFolderFilter,
            selectedCollectionFilter: selectedCollectionFilter,
            showFavoritesOnly: showFavoritesOnly,
            showDuplicatesOnly: showDuplicatesOnly,
            duplicateProjectIDs: cachedDuplicateProjectIDs,
            sortColumn: sortColumn,
            sortAscending: sortAscending
        )
        filterRecomputeTask?.cancel()
        filterRecomputeTask = Task { [weak self] in
            let result = await Self.computeFilteredProjects(snapshot)
            guard let self, !Task.isCancelled, generation == self.filterGeneration else { return }
            self.applyFilteredProjects(result)
        }
    }

    /// Installs a freshly computed filtered list and prunes the selection to
    /// visible rows — otherwise the batch toolbar counts, detail pane, and
    /// Delete key keep acting on projects the user can't see.
    private func applyFilteredProjects(_ result: [ProjectRecord]) {
        cachedFilteredProjects = result
        let visibleIDs = Set(result.map(\.id))
        if !selectedProjectIDs.isSubset(of: visibleIDs) {
            selectedProjectIDs = selectedProjectIDs.intersection(visibleIDs)
        }
    }

    @concurrent
    private static func computeFilteredProjects(_ snapshot: FilterSnapshot) async -> [ProjectRecord] {
        var result = snapshot.projects

        // Apply search filter: FTS match set when available, else legacy
        // substring matching over name/plugins/tags.
        if !snapshot.searchQuery.isEmpty {
            if let matchIDs = snapshot.searchMatchIDs {
                result = result.filter { matchIDs.contains($0.id) }
            } else {
                let query = snapshot.searchQuery.lowercased()
                result = result.filter { project in
                    project.name.lowercased().contains(query) ||
                    project.plugins.contains { $0.lowercased().contains(query) } ||
                    project.userTags.contains { $0.lowercased().contains(query) }
                }
            }
        }

        // Apply category filter
        switch snapshot.selectedFilter {
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

        if let volumeFilter = snapshot.selectedVolumeFilter {
            result = result.filter { $0.sourceVolume == volumeFilter }
        }
        if let statusFilter = snapshot.selectedStatusFilter {
            result = result.filter { $0.completionStatus == statusFilter }
        }
        if let colorLabelFilter = snapshot.selectedColorLabelFilter {
            result = result.filter { $0.colorLabel == colorLabelFilter }
        }
        if let tagFilter = snapshot.selectedTagFilter {
            result = result.filter { $0.userTags.contains(tagFilter) }
        }
        if let pluginFilter = snapshot.selectedPluginFilter {
            result = result.filter { $0.plugins.contains(pluginFilter) }
        }
        if let keyFilter = snapshot.selectedKeyFilter {
            result = result.filter { $0.musicalKeys.contains(keyFilter) }
        }
        if let folderFilter = snapshot.selectedFolderFilter {
            result = result.filter { $0.projectFolderName == folderFilter }
        }
        if let collectionFilter = snapshot.selectedCollectionFilter {
            result = result.filter { $0.collectionID == collectionFilter }
        }
        if snapshot.showFavoritesOnly {
            result = result.filter { $0.isFavorite }
        }
        if snapshot.showDuplicatesOnly {
            result = result.filter { snapshot.duplicateProjectIDs.contains($0.id) }
        }

        // Apply sorting
        result.sort { a, b in
            let comparison: Bool
            switch snapshot.sortColumn {
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
            return snapshot.sortAscending ? comparison : !comparison
        }

        return result
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

    /// Loads the small tables (locations, collections) and starts the projects
    /// observation. The projects table itself is never manually re-fetched:
    /// a GRDB ValueObservation streams every committed change — including each
    /// batch a running scan saves — into `applyObservedProjects`.
    func loadData() async {
        do {
            locations = try await database.fetchAllLocations()
            collections = try await database.fetchAllCollections()
            await removeJunkAutoDetectedLocations()
            if locations.isEmpty {
                await initializeDefaultLocations()
            }
        } catch {
            reportError("Failed to Load Library", error)
        }
        startObservingProjects()
    }

    /// One-time hygiene: DiskArbitration's registration-time replay used to
    /// auto-add simulator disk images and cryptex mounts as scan locations —
    /// enormous trees that never contain projects but were crawled every scan.
    private func removeJunkAutoDetectedLocations() async {
        let junkPrefixes = [
            "/Library/Developer/CoreSimulator",
            "/private/var/run/com.apple.security.cryptexd"
        ]
        let junk = locations.filter { location in
            location.isAutoDetected && junkPrefixes.contains { location.path.hasPrefix($0) }
        }
        guard !junk.isEmpty else { return }
        for location in junk {
            try? await database.deleteLocation(id: location.id)
        }
        let junkIDs = Set(junk.map(\.id))
        locations.removeAll { junkIDs.contains($0.id) }
    }

    private var projectsObservationTask: Task<Void, Never>?

    private func startObservingProjects() {
        guard projectsObservationTask == nil else { return }
        let database = self.database
        projectsObservationTask = Task { [weak self] in
            let observation = ValueObservation.tracking { db in
                try ProjectRecord.fetchAll(db)
            }
            do {
                // Emissions coalesce while one is being applied; fetch + decode
                // run on GRDB's reader queue, never the main actor.
                for try await fetched in observation.values(in: database.reader) {
                    guard let self else { return }
                    await self.applyObservedProjects(fetched)
                    // During a scan, saves land every ~50 files; pacing the
                    // consumer lets GRDB coalesce emissions so the full-table
                    // refetch runs at most ~2Hz instead of per batch.
                    if self.isScanning {
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                }
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.reportError("Library Sync Failed", error)
            }
        }
    }

    /// Applies a projects-table emission: computes all derived caches off the
    /// main actor, then installs everything in one synchronous pass.
    ///
    /// Emissions that merely reconcile an optimistic in-memory update compare
    /// equal and are dropped, so single-record edits keep their cheap delta
    /// path without the full-table re-diff.
    private func applyObservedProjects(_ fetched: [ProjectRecord]) async {
        let generation = projectsMutationGeneration
        guard let caches = await Self.prepareObservedUpdate(fetched: fetched, current: projects) else {
            isInitialLoad = false
            return
        }
        // The in-memory state moved while we were computing; a fresher
        // emission for that write is already queued — let it win.
        guard generation == projectsMutationGeneration else { return }

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
        cachedDuplicateGroups = caches.duplicateGroups
        cachedDuplicatesCount = caches.duplicatesCount
        cachedDuplicateProjectIDs = caches.duplicateProjectIDs
        offlineVolumeNames = caches.offlineVolumes

        // Set projects with didSet recompute suppressed — the caches above were
        // already computed off the main thread.
        isBatchUpdating = true
        projects = fetched
        isBatchUpdating = false
        isInitialLoad = false

        // The precomputed filtered list assumes default sort and no filters.
        if hasNonDefaultFilterOrSort {
            recomputeFilteredProjects()
        } else {
            filterGeneration &+= 1
            applyFilteredProjects(caches.filteredProjects)
        }
    }

    /// nil when `fetched` is identical to the current in-memory state.
    @concurrent
    private static func prepareObservedUpdate(
        fetched: [ProjectRecord],
        current: [ProjectRecord]
    ) async -> ComputedCaches? {
        if fetched == current { return nil }
        return await computeCaches(for: fetched)
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

    func startLocationScan(_ location: LocationRecord, forceReparse: Bool = true) async {
        await runScan(coveringLocations: [location]) { scanner, progress in
            try await scanner.scanLocation(location, forceReparse: forceReparse, progress: progress)
        }
    }

    /// Shared scan driver. The scanner's entry points are @concurrent, so awaiting
    /// them from the main actor runs the crawl/parse work on the concurrent pool;
    /// the wrapping Task exists only to give Stop Scan a handle to cancel.
    ///
    /// `coveringLocations` nil means "every enabled location". Volumes whose
    /// enabled locations are ALL covered by this scan get a fresh replay
    /// baseline, captured BEFORE crawling so changes that land mid-scan fall
    /// after the baseline and replay later.
    private func runScan(
        coveringLocations: [LocationRecord]? = nil,
        _ operation: @escaping @Sendable (ProjectScanner, @escaping @Sendable (ScanProgress) -> Void) async throws -> Int
    ) async {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = .starting

        let coveredPaths = coveringLocations.map { Set($0.map(\.path)) }
        let freshBaselines: [(key: String, target: VolumeWatchTarget, id: FSEventStreamEventId)] =
            volumeWatchTargets().compactMap { target in
                let fullyCovered = coveredPaths.map { covered in
                    target.paths.allSatisfy { covered.contains($0) }
                } ?? true
                guard fullyCovered, let baseline = currentBaseline(for: target) else { return nil }
                return (target.key, target, baseline)
            }

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

        await finishScan(with: result, freshBaselines: freshBaselines)
    }

    func cancelScan() {
        cancelScanAction?()
    }

    private func finishScan(
        with result: Result<Int, Error>,
        freshBaselines: [(key: String, target: VolumeWatchTarget, id: FSEventStreamEventId)]
    ) async {
        // Projects already streamed in via the DB observation during the scan;
        // only the location metadata (counts, last-scanned dates) needs a refresh.
        locations = (try? await database.fetchAllLocations()) ?? locations

        switch result {
        case .success:
            // Each fully-covered volume is now consistent as of its baseline —
            // persist them so future launches/mounts replay deltas, not crawls.
            for baseline in freshBaselines {
                persistBaseline(baseline.id, for: baseline.target)
            }
            ensureFileWatchers()
        case .failure(let error):
            if error is CancellationError {
                // Batches saved before cancellation are already in the DB — show them.
                scanProgress = nil
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
            // The save already streamed in via the DB observation. A nil record
            // means the file is gone — drop its stale index entry.
            if record == nil {
                try? await database.deleteProject(byAlsFilePath: alsPath)
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

        // Each save streams into the UI via the DB observation — no manual apply.
        var updatedCount = 0
        var scannedCount = 0
        for project in projectsToRescan {
            if isCancelled { break }
            scannedCount += 1
            scanProgress = .parsing(current: scannedCount, total: total, projectName: project.name)

            // scanSingleProject is @concurrent — parsing runs off the main actor.
            if (try? await scanner.scanSingleProject(alsFilePath: project.alsFilePath)) != nil {
                updatedCount += 1
            }
        }
        cancelScanAction = nil

        scanProgress = isCancelled ? nil : .completed(projectCount: updatedCount, duration: 0)
        isScanning = false
    }

    func addLocation(path: String) async throws {
        let url = URL(fileURLWithPath: path)
        let displayName = url.lastPathComponent
        let location = LocationRecord.userAdded(path: path, displayName: displayName)
        try await database.saveLocation(location)
        locations.append(location)
        ensureFileWatchers()
    }

    func removeLocation(id: UUID) async throws {
        try await database.deleteLocation(id: id)
        locations.removeAll { $0.id == id }
        ensureFileWatchers()
    }

    // MARK: - File System Watching (FSEvents)

    private static let watchLog = Logger(subsystem: "computerdata.abledex", category: "filewatch")

    /// Traces watcher decisions to the unified log; DEBUG builds also append
    /// to $TMPDIR/abledex-watch.log so scan/replay behavior can be inspected
    /// without a console attached.
    private static func watchTrace(_ message: String) {
        watchLog.log("\(message, privacy: .public)")
        #if DEBUG
        let line = "\(Date()) \(message)\n"
        if let data = line.data(using: .utf8) {
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("abledex-watch.log")
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
        #endif
    }

    /// One FSEvents stream per volume hosting enabled locations, keyed by a
    /// stable volume identity ("boot", or the volume UUID for external drives).
    private var fileWatchers: [String: FileSystemWatcher] = [:]
    private var pendingFileEvents: [FileSystemWatcher.Event] = []
    private var fileEventsDrainTask: Task<Void, Never>?
    private var latestEventIDsByVolume: [String: FSEventStreamEventId] = [:]

    /// A volume with enabled locations on it, resolved to what FSEvents needs.
    private struct VolumeWatchTarget {
        let key: String        // persistence key: "boot" or volume UUID
        let isBoot: Bool
        let device: dev_t
        let volumeRoot: String
        var paths: [String]    // absolute location paths on this volume
    }

    private func volumeWatchTargets() -> [VolumeWatchTarget] {
        var targets: [String: VolumeWatchTarget] = [:]
        for location in locations where location.isEnabled {
            guard FileManager.default.fileExists(atPath: location.path) else { continue }
            let url = URL(fileURLWithPath: location.path)
            guard let values = try? url.resourceValues(forKeys: [.volumeURLKey, .volumeUUIDStringKey]),
                  let volumeRoot = values.volume?.path else { continue }
            var status = stat()
            guard stat(location.path, &status) == 0 else { continue }

            let isBoot = volumeRoot == "/"
            let key = isBoot ? "boot" : (values.volumeUUIDString ?? volumeRoot)
            targets[key, default: VolumeWatchTarget(
                key: key, isBoot: isBoot, device: status.st_dev, volumeRoot: volumeRoot, paths: []
            )].paths.append(location.path)
        }
        return targets.values.map { target in
            var sorted = target
            sorted.paths.sort()
            return sorted
        }
    }

    // MARK: Baseline persistence (per volume)

    private func baselineDefaultsKey(_ volumeKey: String) -> String { "fsEventsBaseline.\(volumeKey)" }
    private func journalDefaultsKey(_ volumeKey: String) -> String { "fsEventsJournal.\(volumeKey)" }

    /// The stored replay baseline for a volume, or nil when replay can't be
    /// trusted. External volumes additionally require that the volume's
    /// journal UUID still matches — device event IDs only mean something
    /// within the journal that issued them (a rebuilt journal, or a different
    /// physical drive with the same mount name, invalidates them).
    private func storedBaseline(for target: VolumeWatchTarget) -> FSEventStreamEventId? {
        let defaults = UserDefaults.standard
        var stored = defaults.string(forKey: baselineDefaultsKey(target.key)).flatMap { UInt64($0) }
        if stored == nil, target.isBoot {
            // Pre-per-volume releases kept a single host-wide key
            stored = defaults.string(forKey: "fsEventsLastEventID").flatMap { UInt64($0) }
        }
        guard let stored else { return nil }
        if !target.isBoot {
            guard let journal = FileSystemWatcher.journalUUID(forDevice: target.device),
                  journal == defaults.string(forKey: journalDefaultsKey(target.key)) else { return nil }
        }
        return stored
    }

    private func persistBaseline(_ id: FSEventStreamEventId, for target: VolumeWatchTarget) {
        let defaults = UserDefaults.standard
        defaults.set(String(id), forKey: baselineDefaultsKey(target.key))
        if !target.isBoot, let journal = FileSystemWatcher.journalUUID(forDevice: target.device) {
            defaults.set(journal, forKey: journalDefaultsKey(target.key))
        }
    }

    /// A fresh "consistent as of now" baseline in the volume's own ID space.
    /// nil when the device's journal isn't available (yet) — a zero ID must
    /// never be persisted or used as sinceWhen, or the stream replays the
    /// volume's entire history.
    private func currentBaseline(for target: VolumeWatchTarget) -> FSEventStreamEventId? {
        if target.isBoot { return FSEventsGetCurrentEventId() }
        let id = FileSystemWatcher.lastEventID(forDevice: target.device)
        return id > 0 ? id : nil
    }

    /// FSEvents' device APIs (journal UUID, last event ID) become available
    /// shortly AFTER the mount notification fires. Poll briefly so replay
    /// validation doesn't misread "not ready yet" as "no journal".
    private func waitForJournal(device: dev_t, timeout: Duration = .seconds(3)) async -> String? {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if let uuid = FileSystemWatcher.journalUUID(forDevice: device) { return uuid }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return FileSystemWatcher.journalUUID(forDevice: device)
    }

    // MARK: Watcher lifecycle

    /// Launch-time indexing. Locations whose volume holds a valid replay
    /// baseline (and that were fully indexed before) are covered by journal
    /// replay — zero filesystem work when nothing changed. Only the remainder
    /// gets a real scan.
    func startAutomaticIndexing() async {
        let autoScan = UserDefaults.standard.object(forKey: "autoScanOnLaunch") as? Bool ?? true
        let targets = volumeWatchTargets()

        var volumeKeyByPath: [String: String] = [:]
        for target in targets {
            for path in target.paths { volumeKeyByPath[path] = target.key }
        }
        let replayableKeys = Set(targets.filter { storedBaseline(for: $0) != nil }.map(\.key))

        let needingScan = locations.filter { location in
            guard location.isEnabled, let key = volumeKeyByPath[location.path] else { return false }
            return location.lastScannedAt == nil || !replayableKeys.contains(key)
        }

        if needingScan.isEmpty || !autoScan {
            ensureFileWatchers()
        } else {
            await runScan(coveringLocations: needingScan) { scanner, progress in
                try await scanner.scanLocations(needingScan, forceReparse: false, progress: progress)
            }
        }
    }

    /// (Re)starts one FSEvents stream per volume with enabled locations —
    /// resuming from the stored baseline when valid (which replays history),
    /// else watching from now. No-op for volumes already watched correctly;
    /// streams for volumes that vanished (unmounts, removed locations) stop.
    private func ensureFileWatchers() {
        let targets = volumeWatchTargets()
        let activeKeys = Set(targets.map(\.key))

        for (key, watcher) in fileWatchers where !activeKeys.contains(key) {
            watcher.stop()
            fileWatchers[key] = nil
        }

        for target in targets {
            if let existing = fileWatchers[target.key], existing.absolutePaths == target.paths { continue }
            fileWatchers[target.key]?.stop()

            let sinceID = storedBaseline(for: target)
                ?? currentBaseline(for: target)
                ?? FSEventStreamEventId(kFSEventStreamEventIdSinceNow)
            let streamTarget: FileSystemWatcher.Target = target.isBoot
                ? .host(paths: target.paths)
                : .device(
                    device: target.device,
                    volumeRoot: target.volumeRoot,
                    relativePaths: target.paths.map { Self.relativePath($0, toVolumeRoot: target.volumeRoot) }
                )

            let volumeKey = target.key
            let watcher = FileSystemWatcher(target: streamTarget, sinceEventID: sinceID) { [weak self] events, latestEventID in
                Task { @MainActor [weak self] in
                    self?.enqueueFileEvents(events, latestEventID: latestEventID, volumeKey: volumeKey)
                }
            }
            fileWatchers[target.key] = watcher
            watcher.start()
        }
    }

    private static func relativePath(_ path: String, toVolumeRoot root: String) -> String {
        guard path != root else { return "" }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }

    private func enqueueFileEvents(
        _ events: [FileSystemWatcher.Event],
        latestEventID: FSEventStreamEventId,
        volumeKey: String
    ) {
        pendingFileEvents.append(contentsOf: events)
        latestEventIDsByVolume[volumeKey] = latestEventID
        guard fileEventsDrainTask == nil else { return }
        fileEventsDrainTask = Task { @MainActor in
            // Extra coalescing on top of the stream latency: Live touches
            // several files per save.
            try? await Task.sleep(for: .milliseconds(500))
            while !pendingFileEvents.isEmpty {
                let batch = pendingFileEvents
                pendingFileEvents.removeAll()
                await processFileEvents(batch)
            }
            fileEventsDrainTask = nil
            // The index has caught up with each volume as of its last event.
            // Never move a baseline backward: replayed (historical) events
            // carry IDs older than a baseline a scan persisted mid-drain, and
            // regressing would re-deliver the same events on every remount.
            let caughtUp = latestEventIDsByVolume
            latestEventIDsByVolume.removeAll()
            let defaults = UserDefaults.standard
            for (key, id) in caughtUp {
                let stored = defaults.string(forKey: baselineDefaultsKey(key)).flatMap { UInt64($0) } ?? 0
                if id > stored {
                    defaults.set(String(id), forKey: baselineDefaultsKey(key))
                }
            }
        }
    }

    /// Applies a coalesced batch of filesystem events to the index:
    /// changed/created .als files re-parse individually; removed .als files
    /// drop their record; directory-level changes (moves, deletions, journal
    /// gaps) trigger an incremental scan, whose pruning handles folder removals.
    private func processFileEvents(_ events: [FileSystemWatcher.Event]) async {
        var locationIDsToScan = Set<UUID>()
        var alsToRescan: [String] = []
        var alsToDelete: [String] = []
        var seenPaths = Set<String>()

        func markContainingLocations(of path: String) {
            for location in locations where location.isEnabled {
                if path == location.path || path.hasPrefix(location.path + "/") {
                    locationIDsToScan.insert(location.id)
                }
            }
        }

        for event in events {
            let path = event.path
            guard seenPaths.insert(path).inserted else { continue }
            Self.watchTrace("event \(String(format: "0x%08x", event.flags)) \(path)")

            // Volume lifecycle is VolumeMonitor's job; hidden-path churn
            // (.fseventsd, .Spotlight-V100, .Trashes, .DS_Store) accompanies
            // every mount and is invisible to the crawler anyway.
            if event.isMountOrUnmount || path.contains("/.") {
                continue
            }
            if event.mustScanSubDirs {
                markContainingLocations(of: path)
                continue
            }
            // Live's own churn on every save — never affects the index
            if path.contains("/Backup/") || path.contains("/Trash/") || path.contains("/Ableton Project Info/") {
                continue
            }
            if path.lowercased().hasSuffix(".als") {
                if FileManager.default.fileExists(atPath: path) {
                    alsToRescan.append(path)
                } else {
                    alsToDelete.append(path)
                }
            } else if event.isDirectory, event.wasCreated || event.wasRemoved || event.wasRenamed {
                // Folder moves deliver no per-file events — only a scan can
                // discover (or prune) the projects inside. Scan just the
                // locations the folder belongs to, not the whole library.
                markContainingLocations(of: path)
            }
        }

        for path in alsToDelete {
            try? await database.deleteProject(byAlsFilePath: path)
        }
        let scanner = self.scanner
        for path in alsToRescan {
            // Saves stream into the UI via the DB observation.
            _ = try? await scanner.scanSingleProject(alsFilePath: path)
        }
        if !locationIDsToScan.isEmpty, !isScanning {
            let affected = locations.filter { locationIDsToScan.contains($0.id) }
            await runScan(coveringLocations: affected) { scanner, progress in
                try await scanner.scanLocations(affected, forceReparse: false, progress: progress)
            }
        }
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

        // Only user-visible drives under /Volumes — NSWorkspace also announces
        // simulator disk images and other mounts that never hold projects.
        guard url.path.hasPrefix("/Volumes/") else { return }

        // Respect the "Scan external volumes automatically" setting
        guard UserDefaults.standard.object(forKey: "scanExternalVolumes") as? Bool ?? true else { return }

        // A single physical mount fires both DiskArbitration and NSWorkspace
        // notifications — without this guard both race saveLocation into a
        // UNIQUE(path) violation and the user gets a spurious error alert.
        guard !mountsBeingHandled.contains(url.path) else { return }
        mountsBeingHandled.insert(url.path)
        defer { mountsBeingHandled.remove(url.path) }

        if let existingLocation = try? await database.fetchLocation(byPath: url.path) {
            guard existingLocation.isEnabled else { return }
            // FSEvents needs a moment to open the just-mounted volume's journal;
            // deciding before it's ready misreads every mount as "no journal".
            var mountStat = stat()
            if stat(url.path, &mountStat) == 0 {
                _ = await waitForJournal(device: mountStat.st_dev)
            }
            // Gold path: the volume's own journal (validated by its UUID)
            // replays everything that changed since it was last indexed —
            // even changes made on another machine — with no crawl at all.
            let target = volumeWatchTargets().first { $0.paths.contains(existingLocation.path) }
            if existingLocation.lastScannedAt != nil, let target, storedBaseline(for: target) != nil {
                Self.watchTrace("mount \(name): replaying journal, no scan")
                ensureFileWatchers()
            } else {
                Self.watchTrace("mount \(name): no valid baseline (target: \(target != nil), scanned: \(existingLocation.lastScannedAt != nil)) — scanning")
                await startLocationScan(existingLocation, forceReparse: false)
            }
        } else {
            let location = LocationRecord.autoDetected(path: url.path, displayName: name)
            do {
                try await database.saveLocation(location)
                locations.append(location)
            } catch {
                reportError("Failed to Add Location", error)
                return
            }
            await startLocationScan(location, forceReparse: false)
        }
    }

    private func handleVolumeUnmounted(url: URL, name: String) {
        // Keep the projects indexed — remembering what lives on unplugged drives
        // is the app's core purpose. Just mark the volume offline.
        if volumeCounts.keys.contains(name) {
            offlineVolumeNames.insert(name)
        }
        // Stop the volume's stream; its replay baseline stays persisted so the
        // next mount resumes from the journal instead of rescanning.
        ensureFileWatchers()
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
        selectedProjectIDs.remove(project.id)
    }

    func deleteSelectedProjects() async throws {
        let idsToDelete = selectedProjectIDs
        try await database.deleteProjects(ids: Array(idsToDelete))
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

    /// Performs a batch update: collects all mutations and saves them in one DB
    /// transaction. The projects observation delivers the new state (with all
    /// caches recomputed off the main actor) — no manual bookkeeping here.
    private func performBatchUpdate(_ mutate: (inout [ProjectRecord]) -> [ProjectRecord]) async throws {
        var mutableProjects = projects
        let updatedRecords = mutate(&mutableProjects)

        guard !updatedRecords.isEmpty else { return }

        try await database.saveProjects(updatedRecords)
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
        // Membership rows are cleared in the same DB transaction; the projects
        // observation reconciles the in-memory records and counts.
        try await database.deleteCollection(id: collection.id)
        collections.removeAll { $0.id == collection.id }
        if selectedCollectionFilter == collection.id {
            selectedCollectionFilter = nil
        }
    }

    /// Assigns (or with nil, removes) the given projects to a music project.
    /// The projects observation delivers the updated membership.
    func assignProjects(_ projectIDs: Set<UUID>, toCollection collectionID: UUID?) async throws {
        guard !projectIDs.isEmpty else { return }
        try await database.assignProjects(ids: Array(projectIDs), toCollection: collectionID)
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
