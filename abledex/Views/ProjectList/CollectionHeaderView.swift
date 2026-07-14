//
//  CollectionHeaderView.swift
//  abledex
//

import SwiftUI

/// Header bar shown above the table when a music project (EP/album) is selected:
/// name, type, editable status, and done-track progress.
struct CollectionHeaderView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.theme) private var theme

    let collection: CollectionRecord

    var body: some View {
        let progress = appState.collectionProgress(collection)

        HStack(spacing: 12) {
            Image(systemName: collection.kind.icon)
                .font(.title2)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(collection.name)
                    .font(.headline)
                Text(collection.kind.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(height: 24)

            Picker("Status", selection: statusBinding) {
                ForEach(CollectionStatus.allCases, id: \.self) { status in
                    Label(status.label, systemImage: status.icon)
                        .tag(status)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .labelsHidden()

            Spacer()

            if progress.total > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(progress.done) of \(progress.total) done")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                        .frame(width: 140)
                }
            } else {
                Text("No tracks yet — right-click projects to add them")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(theme.usesCustomBackground ? AnyShapeStyle(theme.barBackground) : AnyShapeStyle(.bar))
    }

    private var statusBinding: Binding<CollectionStatus> {
        Binding(
            get: { collection.status },
            set: { newStatus in
                var updated = collection
                updated.status = newStatus
                Task {
                    do {
                        try await appState.updateCollection(updated)
                    } catch {
                        appState.reportError("Failed to Update Music Project", error)
                    }
                }
            }
        )
    }
}
