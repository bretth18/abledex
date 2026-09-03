//
//  AppState+Filtering.swift
//  abledex
//

import Foundation

extension AppState {
    // MARK: - Computed Properties

    var filteredProjects: [ProjectRecord] {
        cachedFilteredProjects
    }

    /// Everything the filter/sort pass reads, snapshotted so it can run off
    /// the main actor (filter+sort of a large library takes tens of ms).
    struct FilterSnapshot: Sendable {
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

    func recomputeFilteredProjects() {
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

    /// Prunes selection to visible rows — otherwise the batch toolbar, detail
    /// pane, and Delete key keep acting on projects the user can't see.
    func applyFilteredProjects(_ result: [ProjectRecord]) {
        cachedFilteredProjects = result
        let visibleIDs = Set(result.map(\.id))
        if !selectedProjectIDs.isSubset(of: visibleIDs) {
            selectedProjectIDs = selectedProjectIDs.intersection(visibleIDs)
        }
    }

    @concurrent
    static func computeFilteredProjects(_ snapshot: FilterSnapshot) async -> [ProjectRecord] {
        var result = snapshot.projects

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
