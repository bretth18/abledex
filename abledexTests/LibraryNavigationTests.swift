import Testing
import Foundation
@testable import abledex

/// A music project is a destination, not a filter. These pin that distinction,
/// which is easy to break because navigation and filtering share the same
/// recompute path.
@Suite("Library Navigation")
@MainActor
struct LibraryNavigationTests {

    private func makeState() throws -> AppState {
        AppState(database: try .empty())
    }

    @Test("Opening a music project does not count as an active filter")
    func collectionIsNotAnActiveFilter() throws {
        let state = try makeState()
        let id = UUID()

        state.selectCollection(id)

        #expect(state.selectedCollectionID == id)
        #expect(state.hasActiveFilters == false)
    }

    @Test("A real filter still counts as an active filter")
    func realFilterIsActive() throws {
        let state = try makeState()
        state.selectedTagFilter = "bass"
        #expect(state.hasActiveFilters)
    }

    @Test("Clear Filters keeps you in the music project")
    func clearFiltersKeepsDestination() throws {
        let state = try makeState()
        let id = UUID()

        state.selectCollection(id)
        state.selectedTagFilter = "bass"
        #expect(state.hasActiveFilters)

        state.clearAllFilters()

        #expect(state.selectedTagFilter == nil)
        #expect(state.hasActiveFilters == false)
        #expect(state.selectedCollectionID == id)
    }

    @Test("Opening a music project clears library-wide filters and search")
    func openingClearsFilters() throws {
        let state = try makeState()
        state.selectedTagFilter = "bass"
        state.selectedFilter = .favorites
        state.showDuplicatesOnly = true

        state.selectCollection(UUID())

        #expect(state.selectedTagFilter == nil)
        #expect(state.selectedFilter == .all)
        #expect(state.showDuplicatesOnly == false)
    }

    /// selectCollection leaves selectedFilter at .all, so picking "All Projects"
    /// to leave a collection is a no-op write and cannot rely on didSet.
    @Test("Choosing All Projects leaves the music project")
    func allProjectsLeavesCollection() throws {
        let state = try makeState()
        state.selectCollection(UUID())

        state.selectLibraryFilter(.all)

        #expect(state.selectedCollectionID == nil)
        #expect(state.selectedFilter == .all)
    }

    @Test("Choosing any other Library row also leaves the music project")
    func otherLibraryRowLeavesCollection() throws {
        let state = try makeState()
        state.selectCollection(UUID())

        state.selectLibraryFilter(.favorites)

        #expect(state.selectedCollectionID == nil)
        #expect(state.selectedFilter == .favorites)
    }

    @Test("Sidebar selection reflects the destination in both directions")
    func sidebarSelectionRoundTrips() throws {
        let state = try makeState()
        let id = UUID()

        state.sidebarSelection = .collection(id)
        #expect(state.sidebarSelection == .collection(id))

        state.sidebarSelection = .filter(.recentlyOpened)
        #expect(state.sidebarSelection == .filter(.recentlyOpened))
        #expect(state.selectedCollectionID == nil)
    }

    /// Scoping rows (tag, status, plugin...) narrow whatever is open; they are
    /// not navigation and must not drop you out of a music project.
    @Test("Toggling a scoping filter stays in the music project")
    func scopingFilterStaysInCollection() throws {
        let state = try makeState()
        let id = UUID()
        state.selectCollection(id)

        state.toggleSectionFilter(\.selectedTagFilter, "bass")

        #expect(state.selectedTagFilter == "bass")
        #expect(state.selectedCollectionID == id)
    }

    @Test("showLibrary leaves the music project")
    func showLibraryLeaves() throws {
        let state = try makeState()
        state.selectCollection(UUID())

        state.showLibrary()

        #expect(state.selectedCollectionID == nil)
    }

    @Test("Deleting the open music project leaves its page")
    func deletingOpenCollectionLeaves() async throws {
        let state = try makeState()
        let collection = try await state.createCollection(name: "Test EP", kind: .ep)
        state.selectCollection(collection.id)

        try await state.deleteCollection(collection)

        #expect(state.selectedCollectionID == nil)
    }
}
