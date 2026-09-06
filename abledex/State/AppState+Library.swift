//
//  AppState+Library.swift
//  abledex
//

import Foundation
import GRDB

extension AppState {
    // MARK: - Data Loading

    /// Loads locations/collections and starts the projects observation. The
    /// projects table is never manually re-fetched; the observation streams
    /// every committed change, including each batch a running scan saves.
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

    /// Earlier releases auto-added simulator disk images and cryptex mounts as
    /// locations: enormous trees that never contain projects.
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

    func startObservingProjects() {
        guard projectsObservationTask == nil else { return }
        let database = self.database
        projectsObservationTask = Task { [weak self] in
            let observation = ValueObservation.tracking { db in
                try ProjectRecord.fetchAll(db)
            }
            do {
                // Fetch + decode run on GRDB's reader queue, never the main actor
                for try await fetched in observation.values(in: database.reader) {
                    guard let self else { return }
                    await self.applyObservedProjects(fetched)
                    // Pacing the consumer during scans lets GRDB coalesce
                    // emissions instead of refetching per save batch
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

    /// Applies a projects-table emission: derived caches compute off the main
    /// actor, then everything installs in one synchronous pass. Emissions that
    /// merely reconcile an optimistic in-memory update compare equal and are
    /// dropped, keeping single-record edits on their cheap delta path.
    private func applyObservedProjects(_ fetched: [ProjectRecord]) async {
        let generation = projectsMutationGeneration
        guard let caches = await Self.prepareObservedUpdate(fetched: fetched, current: projects) else {
            isInitialLoad = false
            return
        }
        // State moved while computing; a fresher emission is already queued
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

        // didSet recompute suppressed: the caches above were computed off-main
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

    /// Whether the precomputed default-sorted list can be installed as-is.
    /// Unlike hasActiveFilters this counts selectedCollectionID: a music
    /// project scopes the visible rows even though it is navigation, not a filter.
    var hasNonDefaultFilterOrSort: Bool {
        !searchQuery.isEmpty || selectedFilter != .all || selectedVolumeFilter != nil ||
        selectedStatusFilter != nil || selectedColorLabelFilter != nil || selectedTagFilter != nil ||
        selectedPluginFilter != nil || selectedKeyFilter != nil || selectedFolderFilter != nil ||
        selectedCollectionID != nil || showFavoritesOnly || showDuplicatesOnly ||
        sortColumn != .modifiedDate || sortAscending
    }

    struct ComputedCaches: Sendable {
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
    static func computeCaches(for projects: [ProjectRecord]) async -> ComputedCaches {
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
    /// mount point usually means the drive is unplugged. But volumes can also be
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
}
