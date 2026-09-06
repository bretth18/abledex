//
//  CollectionDetailView.swift
//  abledex
//

import SwiftUI

/// The release page for a music project: what it is, how far along it is, and
/// its tracks in running order.
///
/// A single List so the tracks get native selection, keyboard navigation and
/// drag reordering. The hero and notes are unselectable rows.
struct CollectionDetailView: View {
    let collection: CollectionRecord

    @Environment(AppState.self) private var appState
    @Environment(\.theme) private var theme
    @AppStorage("useCamelotNotation") private var useCamelotNotation = false

    private var tracks: [ProjectRecord] {
        appState.projectsInCollection(collection)
    }

    private var summary: CollectionSummary {
        appState.collectionSummary(collection)
    }

    var body: some View {
        @Bindable var state = appState

        List(selection: $state.selectedProjectIDs) {
            CollectionHeroView(collection: collection, summary: summary)
                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .selectionDisabled()

            Section("Tracks") {
                if tracks.isEmpty {
                    ContentUnavailableView {
                        Label("No Tracks", systemImage: collection.kind.icon)
                    } description: {
                        Text("Right-click projects in the library and choose Music Project > \(collection.name).")
                    }
                    .listRowSeparator(.hidden)
                    .selectionDisabled()
                } else {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        CollectionTrackRow(
                            track: track,
                            position: index + 1,
                            useCamelotNotation: useCamelotNotation
                        )
                    }
                    .onMove(perform: move)
                }
            }

            if let notes = collection.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                        .selectionDisabled()
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(theme.usesCustomBackground ? .hidden : .automatic)
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = tracks
        ordered.move(fromOffsets: source, toOffset: destination)
        Task {
            do {
                try await appState.reorderCollection(collection, to: ordered)
            } catch {
                appState.reportError("Failed to Reorder Tracks", error)
            }
        }
    }
}
