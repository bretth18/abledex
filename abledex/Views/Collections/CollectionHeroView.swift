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

            VStack(alignment: .leading, spacing: 10) {
                Text(collection.name)
                    .font(.system(size: 30, weight: .bold))
                    .lineLimit(2)

                facts

                HStack(spacing: 10) {
                    statusPicker
                    kindPicker
                }

                if summary.trackCount > 0 {
                    progressBar
                }
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .themedCard(cornerRadius: 16)
    }

    /// A tinted block standing in for release artwork, keyed to the release
    /// status so a glance at the page says how far along the record is.
    private var artwork: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                LinearGradient(
                    colors: [statusColor.opacity(0.85), statusColor.opacity(0.35)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 108, height: 108)
            .overlay(
                Image(systemName: collection.kind.icon)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.white.opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            )
    }

    private var facts: some View {
        HStack(spacing: 6) {
            Text(collection.kind.label.uppercased())
                .fontWeight(.semibold)
            separator
            Text("^[\(summary.trackCount) track](inflect: true)")
            if summary.totalDuration > 0 {
                separator
                Text(summary.formattedDuration)
                    .monospacedDigit()
            }
            if let bpm = summary.averageBPM {
                separator
                Text("avg \(Int(bpm.rounded())) BPM")
                    .monospacedDigit()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var separator: some View {
        Text("·").foregroundStyle(.tertiary)
    }

    private var statusPicker: some View {
        Picker("Status", selection: statusBinding) {
            ForEach(CollectionStatus.allCases, id: \.self) { status in
                Label(status.label, systemImage: status.icon).tag(status)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }

    private var kindPicker: some View {
        Picker("Type", selection: kindBinding) {
            ForEach(CollectionKind.allCases, id: \.self) { kind in
                Label(kind.label, systemImage: kind.icon).tag(kind)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.surfacePrimary)
                    Capsule()
                        .fill(statusColor.gradient)
                        .frame(width: max(0, geometry.size.width * progress))
                }
            }
            .frame(height: 8)
            .frame(maxWidth: 320)

            Text("\(summary.doneCount) of \(summary.trackCount) done")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
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
