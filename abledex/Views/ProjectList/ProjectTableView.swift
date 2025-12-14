import SwiftUI

struct ProjectTableView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        Table(of: ProjectRecord.self, selection: $state.selectedProjectID) {
            TableColumn("Name") { project in
                HStack {
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading) {
                        Text(project.name)
                            .lineLimit(1)
                        if project.hasMissingSamples {
                            Label("Missing samples", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .width(min: 150, ideal: 200)

            TableColumn("BPM") { project in
                if let bpm = project.bpm {
                    Text(String(format: "%.0f", bpm))
                        .monospacedDigit()
                } else {
                    Text("-")
                        .foregroundStyle(.secondary)
                }
            }
            .width(50)

            TableColumn("Created") { project in
                if let date = project.createdDate {
                    Text(date, style: .date)
                        .foregroundStyle(.secondary)
                } else {
                    Text("-")
                        .foregroundStyle(.tertiary)
                }
            }
            .width(min: 80, ideal: 100)

            TableColumn("Modified") { project in
                let date = project.modifiedDate ?? project.filesystemModifiedDate
                Text(date, style: .relative)
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100)

            TableColumn("Tracks") { project in
                HStack(spacing: 4) {
                    if project.audioTrackCount > 0 {
                        Label("\(project.audioTrackCount)", systemImage: "waveform")
                            .font(.caption)
                    }
                    if project.midiTrackCount > 0 {
                        Label("\(project.midiTrackCount)", systemImage: "pianokeys")
                            .font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 80)

            TableColumn("Duration") { project in
                if let duration = project.formattedDuration {
                    Text(duration)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    Text("-")
                        .foregroundStyle(.tertiary)
                }
            }
            .width(60)

            TableColumn("Version") { project in
                if let version = project.abletonVersion {
                    Text(version)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("-")
                        .foregroundStyle(.tertiary)
                }
            }
            .width(60)

            TableColumn("Volume") { project in
                Label(project.sourceVolume, systemImage: project.sourceVolume == "Macintosh HD" ? "internaldrive" : "externaldrive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 120)
        } rows: {
            ForEach(appState.filteredProjects) { project in
                TableRow(project)
                    .contextMenu {
                        Button("Open in Ableton") {
                            appState.openProject(project)
                        }
                        Button("Reveal in Finder") {
                            appState.revealProject(project)
                        }
                        Divider()
                        Button("Copy Path") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(project.folderPath, forType: .string)
                        }
                        Divider()
                        Button("Remove from Library", role: .destructive) {
                            Task {
                                try? await appState.deleteProject(project)
                            }
                        }
                    }
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }
}

// MARK: - Sort Header Button

struct SortHeaderButton: View {
    let title: String
    let column: SortColumn
    @Binding var currentColumn: SortColumn
    @Binding var ascending: Bool

    var body: some View {
        Button {
            if currentColumn == column {
                ascending.toggle()
            } else {
                currentColumn = column
                ascending = column == .name // Default ascending for name, descending for dates
            }
        } label: {
            HStack {
                Text(title)
                if currentColumn == column {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
