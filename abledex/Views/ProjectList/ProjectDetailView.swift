import SwiftUI

struct ProjectDetailView: View {
    let project: ProjectRecord
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection

                Divider()

                // Quick actions
                actionsSection

                Divider()

                // Details
                detailsSection

                // Plugins
                if !project.plugins.isEmpty {
                    Divider()
                    pluginsSection
                }

                // Samples
                if !project.samplePaths.isEmpty {
                    Divider()
                    samplesSection
                }

                // Notes
                Divider()
                notesSection
            }
            .padding()
        }
        .frame(minWidth: 280)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "music.note")
                    .font(.title)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading) {
                    Text(project.name)
                        .font(.title2)
                        .fontWeight(.semibold)

                    HStack {
                        Label(project.sourceVolume, systemImage: "externaldrive")
                        if project.hasMissingSamples {
                            Label("Missing samples", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            // BPM and time signature badges
            HStack(spacing: 8) {
                if let bpm = project.bpm {
                    Badge(label: "\(Int(bpm)) BPM", icon: "metronome")
                }
                if let timeSig = project.timeSignature {
                    Badge(label: timeSig, icon: "clock")
                }
                if let duration = project.formattedDuration {
                    Badge(label: duration, icon: "timer")
                }
            }
        }
    }

    private var actionsSection: some View {
        HStack(spacing: 12) {
            Button {
                appState.openProject(project)
            } label: {
                Label("Open", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)

            Button {
                appState.revealProject(project)
            } label: {
                Label("Reveal", systemImage: "folder")
            }
            .buttonStyle(.bordered)

            Spacer()
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Path")
                        .foregroundStyle(.secondary)
                    Text(project.folderPath)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }

                if let version = project.abletonVersion {
                    GridRow {
                        Text("Ableton Version")
                            .foregroundStyle(.secondary)
                        Text(version)
                    }
                }

                GridRow {
                    Text("Audio Tracks")
                        .foregroundStyle(.secondary)
                    Text("\(project.audioTrackCount)")
                }

                GridRow {
                    Text("MIDI Tracks")
                        .foregroundStyle(.secondary)
                    Text("\(project.midiTrackCount)")
                }

                if project.returnTrackCount > 0 {
                    GridRow {
                        Text("Return Tracks")
                            .foregroundStyle(.secondary)
                        Text("\(project.returnTrackCount)")
                    }
                }

                if let created = project.createdDate {
                    GridRow {
                        Text("Created")
                            .foregroundStyle(.secondary)
                        Text(created, style: .date)
                    }
                }

                GridRow {
                    Text("Last Modified")
                        .foregroundStyle(.secondary)
                    Text(project.modifiedDate ?? project.filesystemModifiedDate, style: .date)
                }

                GridRow {
                    Text("Last Indexed")
                        .foregroundStyle(.secondary)
                    Text(project.lastIndexedAt, style: .relative)
                }
            }
            .font(.callout)
        }
    }

    private var pluginsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Plugins (\(project.plugins.count))")
                .font(.headline)

            FlowLayout(spacing: 6) {
                ForEach(project.plugins, id: \.self) { plugin in
                    Text(plugin)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var samplesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Samples (\(project.samplePaths.count))")
                    .font(.headline)

                if project.hasMissingSamples {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(project.samplePaths.prefix(10), id: \.self) { path in
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if project.samplePaths.count > 10 {
                    Text("... and \(project.samplePaths.count - 10) more")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.headline)

            Text(project.userNotes ?? "No notes added")
                .font(.callout)
                .foregroundStyle(project.userNotes == nil ? .tertiary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Supporting Views

struct Badge: View {
    let label: String
    let icon: String

    var body: some View {
        Label(label, systemImage: icon)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.tint.opacity(0.1))
            .foregroundStyle(.tint)
            .clipShape(Capsule())
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)

        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let width = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        let totalHeight = y + rowHeight
        return (CGSize(width: width, height: totalHeight), frames)
    }
}

// MARK: - Empty State

struct ProjectDetailEmptyView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No Project Selected", systemImage: "music.note")
        } description: {
            Text("Select a project from the list to view its details.")
        }
    }
}
