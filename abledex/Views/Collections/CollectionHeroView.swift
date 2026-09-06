//
//  CollectionHeroView.swift
//  abledex
//

import SwiftUI

/// The masthead of a release page: identity, editable status, and progress.
struct CollectionHeroView: View {
    let collection: CollectionRecord
    let summary: CollectionSummary

    @Environment(AppState.self) private var appState
    @Environment(\.theme) private var theme

    private var progress: Double {
        guard summary.trackCount > 0 else { return 0 }
        return Double(summary.doneCount) / Double(summary.trackCount)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            artwork

            VStack(alignment: .leading, spacing: 8) {
                Text(collection.name)
                    .font(.largeTitle.bold())
                    .lineLimit(2)

                facts

                HStack(spacing: 8) {
                    statusPicker
                    kindPicker
                }
                .padding(.top, 4)

                if summary.trackCount > 0 {
                    ProgressView(value: progress) {
                        EmptyView()
                    } currentValueLabel: {
                        Text("\(summary.doneCount) of \(summary.trackCount) done")
                            .monospacedDigit()
                    }
                    .tint(statusColor)
                    .frame(maxWidth: 320)
                    .padding(.top, 4)
                }
            }

            Spacer(minLength: 0)
        }
    }

    /// Stands in for release artwork. Tinted by release status so the page
    /// reads at a glance.
    private var artwork: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(
                LinearGradient(
                    colors: [statusColor.opacity(0.85), statusColor.opacity(0.4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 112, height: 112)
            .overlay {
                Image(systemName: collection.kind.icon)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .accessibilityHidden(true)
    }

    private var facts: some View {
        HStack(spacing: 6) {
            Text(collection.kind.label)
            dot
            Text("^[\(summary.trackCount) track](inflect: true)")
            if summary.totalDuration > 0 {
                dot
                Text(summary.formattedDuration)
            }
            if let bpm = summary.averageBPM {
                dot
                Text("\(Int(bpm.rounded())) BPM average")
            }
        }
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }

    private var dot: some View {
        Text(verbatim: "·").foregroundStyle(.tertiary)
    }

    private var statusPicker: some View {
        Picker("Status", selection: statusBinding) {
            ForEach(CollectionStatus.allCases, id: \.self) { status in
                Label(status.label, systemImage: status.icon).tag(status)
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    private var kindPicker: some View {
        Picker("Type", selection: kindBinding) {
            ForEach(CollectionKind.allCases, id: \.self) { kind in
                Label(kind.label, systemImage: kind.icon).tag(kind)
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    private var statusColor: Color {
        switch collection.status {
        case .planning: theme.statusIdea
        case .inProgress: theme.statusInProgress
        case .mixing: theme.statusMixing
        case .mastering: theme.chartSecondary
        case .released: theme.statusDone
        }
    }

    private var statusBinding: Binding<CollectionStatus> {
        Binding(
            get: { collection.status },
            set: { newStatus in
                var updated = collection
                updated.status = newStatus
                save(updated)
            }
        )
    }

    private var kindBinding: Binding<CollectionKind> {
        Binding(
            get: { collection.kind },
            set: { newKind in
                var updated = collection
                updated.kind = newKind
                save(updated)
            }
        )
    }

    private func save(_ updated: CollectionRecord) {
        Task {
            do {
                try await appState.updateCollection(updated)
            } catch {
                appState.reportError("Failed to Update Music Project", error)
            }
        }
    }
}
