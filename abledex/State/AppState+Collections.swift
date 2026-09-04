//
//  AppState+Collections.swift
//  abledex
//

import Foundation

extension AppState {
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
        // Membership rows clear in the same transaction; observation reconciles
        try await database.deleteCollection(id: collection.id)
        collections.removeAll { $0.id == collection.id }
        if selectedCollectionID == collection.id {
            selectedCollectionID = nil
        }
    }

    /// Assigns (or with nil, removes) the given projects to a music project.
    func assignProjects(_ projectIDs: Set<UUID>, toCollection collectionID: UUID?) async throws {
        guard !projectIDs.isEmpty else { return }
        try await database.assignProjects(ids: Array(projectIDs), toCollection: collectionID)
    }

    func collection(for project: ProjectRecord) -> CollectionRecord? {
        guard let id = project.collectionID else { return nil }
        return collections.first { $0.id == id }
    }

    /// The tracks of a music project, in running order. Projects with no
    /// recorded position sort last, alphabetically, so a collection reads
    /// sensibly before anyone has arranged it.
    func projectsInCollection(_ collection: CollectionRecord) -> [ProjectRecord] {
        projects
            .filter { $0.collectionID == collection.id }
            .sorted { lhs, rhs in
                switch (lhs.collectionPosition, rhs.collectionPosition) {
                case let (left?, right?): return left < right
                case (nil, _?): return false
                case (_?, nil): return true
                case (nil, nil): return lhs.name.localizedCompare(rhs.name) == .orderedAscending
                }
            }
    }

    /// Persists a new running order for a music project.
    func reorderCollection(_ collection: CollectionRecord, to ordered: [ProjectRecord]) async throws {
        try await database.setCollectionOrder(ids: ordered.map(\.id))
    }

    /// Aggregate figures for the release page header.
    func collectionSummary(_ collection: CollectionRecord) -> CollectionSummary {
        let tracks = projectsInCollection(collection)
        let bpms = tracks.compactMap(\.bpm)
        return CollectionSummary(
            trackCount: tracks.count,
            doneCount: tracks.count { $0.completionStatus == .done },
            totalDuration: tracks.compactMap(\.duration).reduce(0, +),
            averageBPM: bpms.isEmpty ? nil : bpms.reduce(0, +) / Double(bpms.count)
        )
    }

    /// Progress of a music project: how many member tracks are Done out of the total.
    func collectionProgress(_ collection: CollectionRecord) -> (done: Int, total: Int) {
        (collectionDoneCounts[collection.id] ?? 0, collectionCounts[collection.id] ?? 0)
    }

    private func sortCollections() {
        collections.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

}

/// Aggregate figures shown on a music project's release page.
struct CollectionSummary {
    var trackCount: Int
    var doneCount: Int
    var totalDuration: Double
    var averageBPM: Double?

    var formattedDuration: String {
        let total = Int(totalDuration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
