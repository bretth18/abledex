import SwiftUI

struct ProjectTableView: View {
    @Environment(AppState.self) private var appState
    @State private var showDeleteConfirmation = false

    var body: some View {
        @Bindable var state = appState

        Table(of: ProjectRecord.self, selection: $state.selectedProjectIDs) {
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
                        if appState.selectedProjectIDs.count > 1 {
                            // Multi-selection context menu
                            Button("Open \(appState.selectedProjectIDs.count) Projects in Ableton") {
                                for proj in appState.selectedProjects {
                                    appState.openProject(proj)
                                }
                            }
                            Button("Reveal \(appState.selectedProjectIDs.count) Projects in Finder") {
                                for proj in appState.selectedProjects {
                                    appState.revealProject(proj)
                                }
                            }
                            Divider()
                            Button("Remove \(appState.selectedProjectIDs.count) Projects from Library", role: .destructive) {
                                showDeleteConfirmation = true
                            }
                        } else {
                            // Single selection context menu
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
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .onDeleteCommand {
            if !appState.selectedProjectIDs.isEmpty {
                showDeleteConfirmation = true
            }
        }
        .confirmationDialog(
            "Remove \(appState.selectedProjectIDs.count) project\(appState.selectedProjectIDs.count == 1 ? "" : "s") from library?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task {
                    try? await appState.deleteSelectedProjects()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This only removes the projects from Abledex's index. The files will not be deleted from disk.")
        }
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
