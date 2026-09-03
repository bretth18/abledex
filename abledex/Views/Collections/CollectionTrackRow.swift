//
//  CollectionTrackRow.swift
//  abledex
//

import SwiftUI

/// One track on a release page: position, name, musical facts, and status.
struct CollectionTrackRow: View {
    let track: ProjectRecord
    let position: Int
    let useCamelotNotation: Bool

    @Environment(AppState.self) private var appState
    @Environment(\.theme) private var theme
    @State private var isHovering = false

    private var isSelected: Bool {
        appState.selectedProjectIDs.contains(track.id)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(position)")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: 24, alignment: .trailing)

            statusDot

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .lineLimit(1)
                    .foregroundStyle(track.colorLabel == .none ? .primary : track.colorLabel.color)
                if track.hasMissingSamples {
                    Label("Missing samples", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 8)

            facts

            statusMenu

            Button {
                appState.openProject(track)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isHovering ? Color.accentColor : Color.secondary.opacity(0.5))
            .help("Open in Ableton Live")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            appState.selectedProjectIDs = [track.id]
        }
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

    private var statusDot: some View {
        Circle()
            .fill(theme.statusColor(for: track.completionStatus))
            .frame(width: 8, height: 8)
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
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }

    private func fact(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .lineLimit(1)
            .frame(width: width, alignment: .trailing)
    }

    private var statusMenu: some View {
        Menu {
            ForEach(CompletionStatus.allCases, id: \.self) { status in
                Button {
                    Task {
                        do {
                            try await appState.updateProjectStatus(track, status: status)
                        } catch {
                            appState.reportError("Failed to Update Status", error)
                        }
                    }
                } label: {
                    Label(status.label, systemImage: track.completionStatus == status ? "checkmark" : status.icon)
                }
            }
        } label: {
            Text(track.completionStatus.label)
                .font(.caption)
                .frame(width: 74, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(theme.statusColor(for: track.completionStatus))
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isSelected ? theme.surfaceSelected : (isHovering ? theme.surfacePrimary : Color.clear))
    }

    private func displayKey(_ key: String) -> String {
        useCamelotNotation ? (CamelotConverter.toCamelot(key) ?? key) : key
    }
}
