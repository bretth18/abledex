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
        if selectedCollectionFilter == collection.id {
            selectedCollectionFilter = nil
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

    /// Progress of a music project: how many member tracks are Done out of the total.
    func collectionProgress(_ collection: CollectionRecord) -> (done: Int, total: Int) {
        (collectionDoneCounts[collection.id] ?? 0, collectionCounts[collection.id] ?? 0)
    }

    private func sortCollections() {
        collections.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

}
