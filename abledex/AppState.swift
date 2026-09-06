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

    // MARK: - State

    var projects: [ProjectRecord] = [] {
        didSet {
            // Invalidates observation emissions computed against the old state
            projectsMutationGeneration &+= 1
            guard !isInitialLoad, !isBatchUpdating else { return }
            recomputeCachedCounts()
            recomputeFilteredProjects()
        }
    }
    var locations: [LocationRecord] = []
    var collections: [CollectionRecord] = []
    var selectedProjectIDs: Set<UUID> = [] {
        didSet {
            // Low-frequency derived flags for the menu bar. Commands must not read
            // selectedProjectIDs/projects directly: every mutation rebuilds the main
            // menu, which raises NSRangeException in NSContextMenuImpl when it lands
            // mid-tracking. Only write on real transitions.
            let single = selectedProjectIDs.count == 1
            if hasSingleSelection != single { hasSingleSelection = single }
        }
    }
    private(set) var hasSingleSelection = false

    // Volumes that have indexed projects but are not currently mounted.
    // Projects on offline drives stay in the index.
    var offlineVolumeNames: Set<String> = []

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
            // Debounce, then resolve matches via the FTS5 index
            searchDebounceTask?.cancel()
            searchDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                if !Task.isCancelled {
                    await resolveSearchMatches()
                }
            }
        }
    }

    /// FTS matches for the current search; nil = empty query or untokenizable
    /// (the filter falls back to substring matching).
    var searchMatchIDs: Set<UUID>?

    private func resolveSearchMatches() async {
        let query = searchQuery
        guard !query.isEmpty else {
            searchMatchIDs = nil
            recomputeFilteredProjects()
            return
        }
        let matches = (try? await database.searchProjectIDs(matching: query)) ?? nil
        guard query == searchQuery else { return } // superseded
        searchMatchIDs = matches
        recomputeFilteredProjects()
    }

    // MARK: - Cached Data (for sidebar performance)
    var statusCounts: [CompletionStatus: Int] = [:]
    var colorLabelCounts: [ColorLabel: Int] = [:]
    var collectionCounts: [UUID: Int] = [:]
    var collectionDoneCounts: [UUID: Int] = [:]
    var volumeCounts: [String: Int] = [:]
    var tagCounts: [String: Int] = [:]
    var pluginCounts: [String: Int] = [:]
    var keyCounts: [String: Int] = [:]
    var folderCounts: [String: Int] = [:]

    // Cached unique values (avoid recomputing on every render)
    var cachedUniqueVolumes: [String] = []
    var cachedUniqueTags: [String] = []
    var cachedUniquePlugins: [String] = []
    var cachedUniqueKeys: [String] = []
    var cachedUniqueFolders: [String] = []
    var cachedFoldersWithMultipleVersions: [String] = []
    var cachedProjectsByFolder: [String: [ProjectRecord]] = [:]
    var cachedDuplicateGroups: [DuplicateGroup] = []
    var cachedDuplicatesCount: Int = 0
    var cachedDuplicateProjectIDs: Set<UUID> = []  // O(1) lookup for detail view

    func recomputeCachedCounts() {
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
            if let collectionID = project.collectionID {
                newCollectionCounts[collectionID, default: 0] += 1
                if project.completionStatus == .done {
                    newCollectionDoneCounts[collectionID, default: 0] += 1
                }
            }
            newStatusCounts[project.completionStatus, default: 0] += 1

            newColorLabelCounts[project.colorLabel, default: 0] += 1

            newVolumeCounts[project.sourceVolume, default: 0] += 1

            newFolderCounts[project.projectFolderName, default: 0] += 1

            for tag in project.userTags {
                newTagCounts[tag, default: 0] += 1
            }

            for plugin in project.plugins {
                newPluginCounts[plugin, default: 0] += 1
            }

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

        // Debounced so the O(n²) pass doesn't re-run on every keystroke or edit
        scheduleDuplicateRecomputation()
    }

    func scheduleDuplicateRecomputation() {
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
    var cancelScanAction: (() -> Void)?

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
    /// The music project being viewed. This is navigation, not a filter: it
    /// does not count towards hasActiveFilters and Clear Filters leaves it
    /// alone. It still scopes the table, which is why the filter pass reads it.
    var selectedCollectionID: UUID? { didSet { recomputeFilteredProjects() } }
    var showFavoritesOnly: Bool = false { didSet { recomputeFilteredProjects() } }
    var showDuplicatesOnly: Bool = false { didSet { recomputeFilteredProjects() } }

    // Cached filtered projects
    var cachedFilteredProjects: [ProjectRecord] = []

    // MARK: - Opening in Ableton Live

    /// A project waiting on the user to choose which Live install opens it.
    struct PendingOpen: Identifiable {
        let id = UUID()
        let project: ProjectRecord
        let installs: [AbletonInstall]
        /// Further projects to open with the same choice (multi-selection).
        var additionalProjects: [ProjectRecord] = []
    }

    var pendingOpen: PendingOpen?
    /// Last discovered Live installs, cached for menus that need them
    /// synchronously. Refreshed on every open and by refreshAbletonInstalls().
    var abletonInstalls: [AbletonInstall] = []

    func refreshAbletonInstalls() async {
        abletonInstalls = await AbletonInstallFinder.findInstalls()
    }

    // MARK: - Derived-Data Bookkeeping

    var isInitialLoad = true
    var isBatchUpdating = false
    var projectsMutationGeneration = 0
    var projectsObservationTask: Task<Void, Never>?
    var filterGeneration = 0
    var filterRecomputeTask: Task<Void, Never>?
    var searchDebounceTask: Task<Void, Never>?
    var duplicateDebounceTask: Task<Void, Never>?

    // MARK: - File System Watching

    /// One FSEvents stream per volume hosting enabled locations, keyed by a
    /// stable volume identity ("boot", or the volume UUID for external drives).
    var fileWatchers: [String: FileSystemWatcher] = [:]
    var pendingFileEvents: [FileSystemWatcher.Event] = []
    var fileEventsDrainTask: Task<Void, Never>?
    var latestEventIDsByVolume: [String: FSEventStreamEventId] = [:]
    var workspaceObservers: [NSObjectProtocol] = []
    var mountsBeingHandled: Set<String> = []
    var volumeMonitor: VolumeMonitor?

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
}
