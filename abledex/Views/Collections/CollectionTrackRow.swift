//
//  CollectionTrackRow.swift
//  abledex
//

import SwiftUI

/// One track on a release page: position, name, musical facts, and status.
/// Selection and reordering come from the enclosing List.
struct CollectionTrackRow: View {
    let track: ProjectRecord
    let position: Int
    let useCamelotNotation: Bool

    @Environment(AppState.self) private var appState
    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Text("\(position)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)

            Circle()
                .fill(theme.statusColor(for: track.completionStatus))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .lineLimit(1)
                    .foregroundStyle(track.colorLabel == .none ? .primary : track.colorLabel.color)
                if track.hasMissingSamples {
                    Label("Missing samples", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 8)

            facts
            statusMenu

            Button {
                appState.openProject(track)
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)
            .opacity(isHovering ? 1 : 0)
            .help("Open in Ableton Live")
        }
        .padding(.vertical, 4)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Open in Ableton") { appState.openProject(track) }
            if appState.abletonInstalls.count > 1 {
                Menu("Open With") { OpenWithMenuItems(project: track) }
            }
            Button("Reveal in Finder") { appState.revealProject(track) }
            Divider()
            Button("Remove from Music Project") {
                Task {
                    do {
                        try await appState.assignProjects([track.id], toCollection: nil)
                    } catch {
                        appState.reportError("Failed to Update Music Project", error)
                    }
                }
            }
        }
    }

    private var facts: some View {
        HStack(spacing: 14) {
            if let bpm = track.bpm {
                fact("\(Int(bpm))", width: 34)
            }
            if let key = track.musicalKeys.first {
                fact(displayKey(key), width: 46)
            }
            if let duration = track.formattedDuration {
                fact(duration, width: 42)
            }
        }
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }

    private func fact(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .lineLimit(1)
            .frame(width: width, alignment: .trailing)
    }

    private var statusMenu: some View {
        Picker("Status", selection: statusBinding) {
            ForEach(CompletionStatus.allCases, id: \.self) { status in
                Label(status.label, systemImage: status.icon).tag(status)
            }
        }
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
    }

    private var statusBinding: Binding<CompletionStatus> {
        Binding(
            get: { track.completionStatus },
            set: { status in
                Task {
                    do {
                        try await appState.updateProjectStatus(track, status: status)
                    } catch {
                        appState.reportError("Failed to Update Status", error)
                    }
                }
            }
        )
    }

    private func displayKey(_ key: String) -> String {
        useCamelotNotation ? (CamelotConverter.toCamelot(key) ?? key) : key
    }
}
