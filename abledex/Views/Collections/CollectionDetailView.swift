//
//  CollectionDetailView.swift
//  abledex
//

import SwiftUI

/// The release page for a music project: what it is, how far along it is, and
/// its tracks in running order.
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CollectionHeroView(collection: collection, summary: summary)
                tracklist
                notes
            }
            .padding(20)
        }
        .background(theme.usesCustomBackground ? theme.background : nil)
    }

    // MARK: - Tracklist

    @ViewBuilder
    private var tracklist: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tracks")
                    .font(.headline)
                Spacer()
                if summary.trackCount > 1 {
                    Text("Drag to reorder")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if tracks.isEmpty {
                ContentUnavailableView {
                    Label("No Tracks Yet", systemImage: collection.kind.icon)
                } description: {
                    Text("Right-click projects in the library and choose Music Project › \(collection.name).")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .themedCard()
            } else {
                LazyVStack(spacing: 2) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        CollectionTrackRow(
                            track: track,
                            position: index + 1,
                            useCamelotNotation: useCamelotNotation
                        )
                        .draggable(track.id.uuidString) {
                            Text(track.name).padding(6)
                        }
                        .dropDestination(for: String.self) { items, _ in
                            move(items, above: index)
                        }
                    }
                }
                .themedCard()
            }
        }
    }

    @ViewBuilder
    private var notes: some View {
        if let notes = collection.notes, !notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Notes")
                    .font(.headline)
                Text(notes)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .themedCard()
            }
        }
    }

    /// Moves the dragged track to `destination`, then persists the new order.
    private func move(_ items: [String], above destination: Int) -> Bool {
        guard let dragged = items.first.flatMap(UUID.init(uuidString:)) else { return false }
        var ordered = tracks
        guard let source = ordered.firstIndex(where: { $0.id == dragged }), source != destination else { return false }

        let track = ordered.remove(at: source)
        ordered.insert(track, at: min(destination, ordered.count))

        Task {
            do {
                try await appState.reorderCollection(collection, to: ordered)
            } catch {
                appState.reportError("Failed to Reorder Tracks", error)
            }
        }
        return true
    }
}
