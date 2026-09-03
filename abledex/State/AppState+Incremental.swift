//
//  AppState+Incremental.swift
//  abledex
//

import Foundation

extension AppState {
    // MARK: - Incremental Updates

    /// Applies a single-record change without re-aggregating the whole library.
    /// The `projects` didSet path does a full recount and reschedules O(n²)
    /// duplicate detection, which one favorite/status/tag click does not warrant.
    func applyUpdatedProject(_ updated: ProjectRecord) {
        guard let index = projects.firstIndex(where: { $0.id == updated.id }) else { return }
        let old = projects[index]

        isBatchUpdating = true
        projects[index] = updated
        isBatchUpdating = false

        applyCacheDelta(old: old, new: updated)
        recomputeFilteredProjects()

        // Duplicate detection only depends on hash/BPM/plugins, so pure metadata
        // edits skip the O(n²) reschedule.
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

        // Folder name only changes on rescan/move; fall back to the full pass then.
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

}
