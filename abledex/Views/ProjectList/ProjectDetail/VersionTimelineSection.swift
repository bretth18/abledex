//
//  VersionTimelineSection.swift
//  abledex
//
//  Created by Brett Henderson on 12/23/25.
//

import SwiftUI

struct VersionTimelineSection: View {
    let project: ProjectRecord
    @Environment(AppState.self) private var appState
    @State private var isExpanded = true

    private var versions: [ProjectRecord] {
        appState.versionsInSameFolder(as: project)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(versions.enumerated()), id: \.element.id) { index, version in
                    versionRow(version, index: index, isLast: index == versions.count - 1)
                }
            }
        } label: {
            HStack {
                Text("Version History")
                    .font(.headline)
                Spacer()
                Text("\(versions.count) versions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func versionRow(_ version: ProjectRecord, index: Int, isLast: Bool) -> some View {
        let isCurrent = version.id == project.id
        let previousVersion = index > 0 ? versions[index - 1] : nil

        HStack(alignment: .top, spacing: 12) {
            // Timeline connector
            VStack(spacing: 0) {
                Circle()
                    .fill(isCurrent ? Color.accentColor : Color.secondary.opacity(0.5))
                    .frame(width: 10, height: 10)

                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 10)

            // Version info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(version.name)
                        .font(.callout)
                        .fontWeight(isCurrent ? .semibold : .regular)
                        .foregroundStyle(isCurrent ? .primary : .secondary)
                        .lineLimit(1)

                    if isCurrent {
                        Text("Current")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.2))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }

                    Spacer()

                    if !isCurrent {
                        Button {
                            selectVersion(version)
                        } label: {
                            Image(systemName: "arrow.right.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("View this version")
                    }
                }

                HStack(spacing: 8) {
                    Text(version.modifiedDate ?? version.filesystemModifiedDate, style: .date)
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    if let diff = computeDiff(from: previousVersion, to: version) {
                        diffBadges(diff)
                    }
                }

                // Quick stats
                HStack(spacing: 12) {
                    if let bpm = version.bpm {
                        Label("\(Int(bpm))", systemImage: "metronome")
                    }
                    Label("\(version.totalTrackCount)", systemImage: "slider.horizontal.3")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .padding(.bottom, isLast ? 0 : 12)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isCurrent {
                selectVersion(version)
            }
        }
    }

    @ViewBuilder
    private func diffBadges(_ diff: VersionDiff) -> some View {
        HStack(spacing: 4) {
            if let bpmChange = diff.bpmChanged {
                let delta = (bpmChange.to ?? 0) - (bpmChange.from ?? 0)
                if delta != 0 {
                    Text(delta > 0 ? "+\(Int(delta)) BPM" : "\(Int(delta)) BPM")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(delta > 0 ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                        .foregroundStyle(delta > 0 ? .green : .orange)
                        .clipShape(Capsule())
                }
            }

            if diff.tracksDelta != 0 {
                Text(diff.tracksDelta > 0 ? "+\(diff.tracksDelta) tracks" : "\(diff.tracksDelta) tracks")
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(diff.tracksDelta > 0 ? Color.blue.opacity(0.2) : Color.red.opacity(0.2))
                    .foregroundStyle(diff.tracksDelta > 0 ? .blue : .red)
                    .clipShape(Capsule())
            }

            if !diff.pluginsAdded.isEmpty {
                Text("+\(diff.pluginsAdded.count) plugins")
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.purple.opacity(0.2))
                    .foregroundStyle(.purple)
                    .clipShape(Capsule())
            }
        }
    }

    private func selectVersion(_ version: ProjectRecord) {
        appState.selectedProjectIDs = [version.id]
    }

    private func computeDiff(from older: ProjectRecord?, to newer: ProjectRecord) -> VersionDiff? {
        guard let older = older else { return nil }

        let tracksDelta = newer.totalTrackCount - older.totalTrackCount

        var bpmChanged: (from: Double?, to: Double?)? = nil
        if older.bpm != newer.bpm {
            bpmChanged = (from: older.bpm, to: newer.bpm)
        }

        let oldPlugins = Set(older.plugins)
        let newPlugins = Set(newer.plugins)
        let pluginsAdded = Array(newPlugins.subtracting(oldPlugins))
        let pluginsRemoved = Array(oldPlugins.subtracting(newPlugins))

        // Only return diff if there are changes
        if bpmChanged == nil && tracksDelta == 0 && pluginsAdded.isEmpty && pluginsRemoved.isEmpty {
            return nil
        }

        return VersionDiff(
            bpmChanged: bpmChanged,
            tracksDelta: tracksDelta,
            pluginsAdded: pluginsAdded,
            pluginsRemoved: pluginsRemoved
        )
    }
}

struct VersionDiff {
    var bpmChanged: (from: Double?, to: Double?)?
    var tracksDelta: Int
    var pluginsAdded: [String]
    var pluginsRemoved: [String]
}
