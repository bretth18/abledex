//
//  ProjectTableView.swift
//  abledex
//
//  Created by Brett Henderson on 12/14/25.
//

import SwiftUI

struct ProjectTableView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.theme) private var theme
    @AppStorage("showMissingSamplesWarning") private var showMissingSamplesWarning = true
    @State private var showDeleteConfirmation = false
    @State private var showBatchTagSheet = false
    @State private var batchTagInput = ""

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 0) {
            // Batch operations toolbar
            if appState.selectedProjectIDs.count > 1 {
                batchToolbar
            }

            Table(of: ProjectRecord.self, selection: $state.selectedProjectIDs) {
                TableColumn("") { project in
                    Button {
                        Task {
                            do {
                                try await appState.toggleFavorite(project)
                            } catch {
                                appState.reportError("Failed to Update Favorite", error)
                            }
                        }
                    } label: {
                        Image(systemName: project.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(project.isFavorite ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(project.isFavorite ? "Remove Favorite" : "Add Favorite")
                }
                .width(24)

                TableColumn("Name") { project in
                    HStack {
                        Image(systemName: "music.note")
                            .foregroundStyle(project.colorLabel.rawValue != 0 ? project.colorLabel.color : .secondary)
                        VStack(alignment: .leading) {
                            Text(project.name)
                                .lineLimit(1)
                                .foregroundStyle(project.colorLabel.color)
                            if project.hasMissingSamples && showMissingSamplesWarning {
                                Label("Missing samples", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                            if !appState.isVolumeOnline(project) {
                                Label("Drive offline", systemImage: "externaldrive.badge.xmark")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .opacity(appState.isVolumeOnline(project) ? 1 : 0.5)
                }
                .width(min: 150, ideal: 200)

                TableColumn("Status") { project in
                    HStack(spacing: 4) {
                        Image(systemName: project.completionStatus.icon)
                            .foregroundStyle(theme.statusColor(for: project.completionStatus))
                        Text(project.completionStatus.label)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 100)

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
                    // Formatted once — Text(_, style: .relative) schedules per-second
                    // re-renders for every visible row
                    Text(date.formatted(.relative(presentation: .named)))
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
                    Label(
                        project.sourceVolume,
                        systemImage: appState.isVolumeOnline(project)
                            ? (project.sourceVolume == "Macintosh HD" ? "internaldrive" : "externaldrive")
                            : "externaldrive.badge.xmark"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 120)
                
                /// TODO: refactor table to allow more than 10 columns so we can add this back in
//                TableColumn("Color") { project in
//                    Label(String(project.colorLabel.label), systemImage: "tag.fill")
//                        .font(.caption)
//                        .foregroundStyle(project.colorLabel.color)
//                }
//                .width(min: 80, ideal: 100)
                

                
            } rows: {
                ForEach(appState.filteredProjects) { project in
                    TableRow(project)
                        .contextMenu {
                            contextMenu(for: project)
                        }
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: !theme.usesCustomBackground))
            .scrollContentBackground(theme.usesCustomBackground ? .hidden : .automatic)
            .overlay {
                if appState.filteredProjects.isEmpty {
                    if appState.projects.isEmpty {
                        ContentUnavailableView {
                            Label("No Projects Yet", systemImage: "music.note.list")
                        } description: {
                            Text("Scan your locations to index your Ableton projects and sets.")
                        } actions: {
                            Button("Scan All Locations") {
                                Task { await appState.startScan() }
                            }
                            .disabled(appState.isScanning)
                        }
                    } else if !appState.searchQuery.isEmpty {
                        ContentUnavailableView.search(text: appState.searchQuery)
                    } else {
                        ContentUnavailableView {
                            Label("No Matching Projects", systemImage: "line.3.horizontal.decrease.circle")
                        } description: {
                            Text("No projects match the current filters.")
                        } actions: {
                            Button("Clear Filters") {
                                appState.clearAllFilters()
                            }
                        }
                    }
                }
            }
            .onDeleteCommand {
                if !appState.selectedProjectIDs.isEmpty {
                    showDeleteConfirmation = true
                }
            }
            // Keyboard shortcuts
            .onKeyPress(.return) {
                if let project = appState.selectedProject {
                    appState.openProject(project)
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.space) {
                if let project = appState.selectedProject {
                    appState.revealProject(project)
                    return .handled
                }
                return .ignored
            }
        }
        .confirmationDialog(
            "Remove ^[\(appState.selectedProjectIDs.count) project](inflect: true) from library?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task {
                    do {
                        try await appState.deleteSelectedProjects()
                    } catch {
                        appState.reportError("Failed to Remove Projects", error)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This only removes the projects from Abledex's index. The files will not be deleted from disk.")
        }
        .sheet(isPresented: $showBatchTagSheet) {
            batchTagSheet
        }
    }

    // MARK: - Batch Toolbar

    private var batchToolbar: some View {
        HStack(spacing: 16) {
            Text("\(appState.selectedProjectIDs.count) selected")
                .font(.headline)

            Divider()
                .frame(height: 20)

            // Status menu
            Menu {
                ForEach(CompletionStatus.allCases, id: \.self) { status in
                    Button {
                        Task {
                            try? await appState.batchSetStatus(status)
                        }
                    } label: {
                        Label(status.label, systemImage: status.icon)
                    }
                }
            } label: {
                Label("Set Status", systemImage: "checkmark.circle")
            }
            .menuStyle(.borderlessButton)

            Button {
                showBatchTagSheet = true
            } label: {
                Label("Add Tag", systemImage: "tag")
            }
            .buttonStyle(.borderless)

            Button {
                Task {
                    try? await appState.batchToggleFavorite(true)
                }
            } label: {
                Label("Favorite All", systemImage: "star.fill")
            }
            .buttonStyle(.borderless)

            Button {
                Task {
                    try? await appState.batchToggleFavorite(false)
                }
            } label: {
                Label("Unfavorite All", systemImage: "star.slash")
            }
            .buttonStyle(.borderless)

            Spacer()

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Remove", systemImage: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(theme.usesCustomBackground ? AnyShapeStyle(theme.barBackground) : AnyShapeStyle(.bar))
    }

    // MARK: - Batch Tag Sheet

    private var batchTagSheet: some View {
        VStack(spacing: 16) {
            Text("Add Tag to \(appState.selectedProjectIDs.count) Projects")
                .font(.headline)

            TextField("Tag name", text: $batchTagInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)

            HStack {
                Button("Cancel") {
                    batchTagInput = ""
                    showBatchTagSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Add") {
                    let tag = batchTagInput.trimmingCharacters(in: .whitespaces)
                    if !tag.isEmpty {
                        Task {
                            try? await appState.batchAddTag(tag)
                            batchTagInput = ""
                            showBatchTagSheet = false
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(batchTagInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenu(for project: ProjectRecord) -> some View {
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

            Menu("Set Status") {
                ForEach(CompletionStatus.allCases, id: \.self) { status in
                    Button {
                        Task {
                            try? await appState.batchSetStatus(status)
                        }
                    } label: {
                        Label(status.label, systemImage: status.icon)
                    }
                }
            }

            Button("Favorite All") {
                Task {
                    try? await appState.batchToggleFavorite(true)
                }
            }

            musicProjectMenu(for: appState.selectedProjectIDs)

            Button("Re-scan \(appState.selectedProjectIDs.count) Projects") {
                Task {
                    await appState.rescanProjects(appState.selectedProjects)
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

            Button {
                Task {
                    try? await appState.toggleFavorite(project)
                }
            } label: {
                Label(
                    project.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: project.isFavorite ? "star.slash" : "star"
                )
            }

            Menu("Set Status") {
                ForEach(CompletionStatus.allCases, id: \.self) { status in
                    Button {
                        Task {
                            try? await appState.updateProjectStatus(project, status: status)
                        }
                    } label: {
                        HStack {
                            Label(status.label, systemImage: status.icon)
                            if project.completionStatus == status {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            musicProjectMenu(for: [project.id], currentCollectionID: project.collectionID)

            Button("Re-scan Project") {
                Task {
                    await appState.rescanProject(project)
                }
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

    // MARK: - Music Project Menu

    @ViewBuilder
    private func musicProjectMenu(for projectIDs: Set<UUID>, currentCollectionID: UUID? = nil) -> some View {
        Menu("Music Project") {
            ForEach(appState.collections) { collection in
                Button {
                    assign(projectIDs, to: collection.id)
                } label: {
                    if currentCollectionID == collection.id {
                        Label(collection.name, systemImage: "checkmark")
                    } else {
                        Label(collection.name, systemImage: collection.kind.icon)
                    }
                }
            }

            if !appState.collections.isEmpty {
                Divider()
            }

            if currentCollectionID != nil {
                Button("Remove from Music Project") {
                    assign(projectIDs, to: nil)
                }
            }
        }
    }

    private func assign(_ projectIDs: Set<UUID>, to collectionID: UUID?) {
        Task {
            do {
                try await appState.assignProjects(projectIDs, toCollection: collectionID)
            } catch {
                appState.reportError("Failed to Update Music Project", error)
            }
        }
    }
}


