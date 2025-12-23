//
//  SidebarView.swift
//  abledex
//
//  Created by Brett Henderson on 12/14/25.
//

import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("useCamelotNotation") private var useCamelotNotation = false
    @State private var isLibraryExpanded = true
    @State private var isStatusExpanded = true
    @State private var isPluginsExpanded = false
    @State private var isKeysExpanded = false
    @State private var isFoldersExpanded = false
    @State private var isTagsExpanded = true
    @State private var isColorLabelsExpanded = true
    @State private var isVolumesExpanded = true
    @State private var isLocationsExpanded = true

    var body: some View {
        @Bindable var state = appState

        List(selection: $state.selectedFilter) {
            Text(appTitle)
                .font(.largeTitle.bold())
                .padding(.vertical, 4)

            Section(isExpanded: $isLibraryExpanded) {
                ForEach(ProjectFilter.allCases, id: \.self) { filter in
                    Label {
                        HStack {
                            Text(filter.rawValue)
                            Spacer()
                            if filter == .all {
                                Text("\(appState.projectCount)")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                    } icon: {
                        filterIcon(for: filter)
                    }
                    .tag(filter)
                }

                // Duplicates filter
                if appState.duplicatesCount > 0 {
                    Button {
                        appState.showDuplicatesOnly.toggle()
                    } label: {
                        Label {
                            HStack {
                                Text("Duplicates")
                                Spacer()
                                Text("\(appState.duplicatesCount)")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        } icon: {
                            Image(systemName: "doc.on.doc")
                                .foregroundStyle(.red)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        appState.showDuplicatesOnly
                            ? Color.accentColor.opacity(0.2)
                            : Color.clear
                    )
                }
            } header: {
                Text("Library")
            }

            Section(isExpanded: $isStatusExpanded) {
                ForEach(CompletionStatus.allCases, id: \.self) { status in
                    Button {
                        if appState.selectedStatusFilter == status {
                            appState.selectedStatusFilter = nil
                        } else {
                            appState.selectedStatusFilter = status
                        }
                    } label: {
                        Label {
                            HStack {
                                Text(status.label)
                                Spacer()
                                Text("\(statusCount(for: status))")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        } icon: {
                            Image(systemName: status.icon)
                                .foregroundStyle(statusColor(for: status))
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        appState.selectedStatusFilter == status
                            ? Color.accentColor.opacity(0.2)
                            : Color.clear
                    )
                }
            } header: {
                Text("Status")
            }

            if !appState.uniquePlugins.isEmpty {
                Section(isExpanded: $isPluginsExpanded) {
                    ForEach(appState.uniquePlugins.prefix(20), id: \.self) { plugin in
                        Button {
                            if appState.selectedPluginFilter == plugin {
                                appState.selectedPluginFilter = nil
                            } else {
                                appState.selectedPluginFilter = plugin
                            }
                        } label: {
                            Label {
                                HStack {
                                    Text(plugin)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(pluginCount(for: plugin))")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                            } icon: {
                                Image(systemName: "puzzlepiece.extension")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            appState.selectedPluginFilter == plugin
                                ? Color.accentColor.opacity(0.2)
                                : Color.clear
                        )
                    }
                    if appState.uniquePlugins.count > 20 {
                        Text("+ \(appState.uniquePlugins.count - 20) more...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Plugins")
                }
            }

            if !appState.uniqueKeys.isEmpty {
                Section(isExpanded: $isKeysExpanded) {
                    ForEach(appState.uniqueKeys, id: \.self) { key in
                        Button {
                            if appState.selectedKeyFilter == key {
                                appState.selectedKeyFilter = nil
                            } else {
                                appState.selectedKeyFilter = key
                            }
                        } label: {
                            Label {
                                HStack {
                                    Text(displayKey(key))
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(keyCount(for: key))")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                            } icon: {
                                Image(systemName: "music.note")
                                    .foregroundStyle(.pink)
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            appState.selectedKeyFilter == key
                                ? Color.accentColor.opacity(0.2)
                                : Color.clear
                        )
                    }
                } header: {
                    Text("Keys")
                }
            }

            if !appState.uniqueFolders.isEmpty {
                Section(isExpanded: $isFoldersExpanded) {
                    ForEach(foldersWithMultipleVersions.prefix(20), id: \.self) { folder in
                        Button {
                            if appState.selectedFolderFilter == folder {
                                appState.selectedFolderFilter = nil
                            } else {
                                appState.selectedFolderFilter = folder
                            }
                        } label: {
                            Label {
                                HStack {
                                    Text(folder)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(folderCount(for: folder))")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                            } icon: {
                                Image(systemName: "folder")
                                    .foregroundStyle(.cyan)
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            appState.selectedFolderFilter == folder
                                ? Color.accentColor.opacity(0.2)
                                : Color.clear
                        )
                    }
                    if foldersWithMultipleVersions.count > 20 {
                        Text("+ \(foldersWithMultipleVersions.count - 20) more...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Project Folders")
                }
            }

            if !appState.uniqueTags.isEmpty {
                Section(isExpanded: $isTagsExpanded) {
                    ForEach(appState.uniqueTags, id: \.self) { tag in
                        Button {
                            if appState.selectedTagFilter == tag {
                                appState.selectedTagFilter = nil
                            } else {
                                appState.selectedTagFilter = tag
                            }
                        } label: {
                            Label {
                                HStack {
                                    Text(tag)
                                    Spacer()
                                    Text("\(tagCount(for: tag))")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                            } icon: {
                                Image(systemName: "tag")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            appState.selectedTagFilter == tag
                                ? Color.accentColor.opacity(0.2)
                                : Color.clear
                        )
                    }
                } header: {
                    Text("Tags")
                }
            }

            Section(isExpanded: $isColorLabelsExpanded) {
                ForEach(ColorLabel.allCases.filter { $0 != .none }, id: \.self) { label in
                    let count = appState.colorLabelCount(for: label)
                    if count > 0 {
                        Button {
                            if appState.selectedColorLabelFilter == label {
                                appState.selectedColorLabelFilter = nil
                            } else {
                                appState.selectedColorLabelFilter = label
                            }
                        } label: {
                            Label {
                                HStack {
                                    Text(label.label)
                                    Spacer()
                                    Text("\(count)")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                            } icon: {
                                Image(systemName: "circle.fill")
                                    .foregroundStyle(colorForLabel(label))
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            appState.selectedColorLabelFilter == label
                                ? Color.accentColor.opacity(0.2)
                                : Color.clear
                        )
                    }
                }
            } header: {
                Text("Color Labels")
            }

            if !appState.uniqueVolumes.isEmpty {
                Section(isExpanded: $isVolumesExpanded) {
                    ForEach(appState.uniqueVolumes, id: \.self) { volume in
                        Button {
                            if appState.selectedVolumeFilter == volume {
                                appState.selectedVolumeFilter = nil
                            } else {
                                appState.selectedVolumeFilter = volume
                            }
                        } label: {
                            Label {
                                HStack {
                                    Text(volume)
                                    Spacer()
                                    Text("\(projectCount(for: volume))")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                            } icon: {
                                Image(systemName: volumeIcon(for: volume))
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            appState.selectedVolumeFilter == volume
                                ? Color.accentColor.opacity(0.2)
                                : Color.clear
                        )
                    }
                } header: {
                    Text("Volumes")
                }
            }

            Section(isExpanded: $isLocationsExpanded) {
                ForEach(appState.locations) { location in
                    Label {
                        VStack(alignment: .leading) {
                            Text(location.displayName)
                            Text(location.path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } icon: {
                        Image(systemName: location.isAutoDetected ? "folder.fill" : "folder.badge.person.crop")
                    }
                    .contextMenu {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: location.path)
                        }
                        Divider()
                        Button("Remove Location", role: .destructive) {
                            Task {
                                try? await appState.removeLocation(id: location.id)
                            }
                        }
                    }
                }

                Button {
                    selectFolder()
                } label: {
                    Label("Add Folder...", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            } header: {
                Text("Locations")
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                // Active filters indicator
                if hasActiveFilters {
                    HStack {
                        Text("Filters active")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear") {
                            clearAllFilters()
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                    }
                    .padding(.horizontal)
                }

                if appState.isScanning {
                    scanProgressView
                }

                Button {
                    Task {
                        await appState.startScan()
                    }
                } label: {
                    Label(
                        appState.isScanning ? "Scanning..." : "Scan All Locations",
                        systemImage: appState.isScanning ? "arrow.triangle.2.circlepath" : "arrow.clockwise"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isScanning)
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private var hasActiveFilters: Bool {
        appState.selectedStatusFilter != nil ||
        appState.selectedColorLabelFilter != nil ||
        appState.selectedVolumeFilter != nil ||
        appState.selectedTagFilter != nil ||
        appState.selectedPluginFilter != nil ||
        appState.selectedKeyFilter != nil ||
        appState.selectedFolderFilter != nil ||
        appState.showFavoritesOnly ||
        appState.showDuplicatesOnly ||
        appState.selectedFilter != .all
    }

    private func clearAllFilters() {
        appState.selectedStatusFilter = nil
        appState.selectedColorLabelFilter = nil
        appState.selectedVolumeFilter = nil
        appState.selectedTagFilter = nil
        appState.selectedPluginFilter = nil
        appState.selectedKeyFilter = nil
        appState.selectedFolderFilter = nil
        appState.showFavoritesOnly = false
        appState.showDuplicatesOnly = false
        appState.selectedFilter = .all
    }

    private var foldersWithMultipleVersions: [String] {
        appState.projectsByFolder
            .filter { $0.value.count > 1 }
            .keys
            .sorted()
    }

    @ViewBuilder
    private var scanProgressView: some View {
        if let progress = appState.scanProgress {
            VStack(alignment: .leading, spacing: 4) {
                switch progress {
                case .starting:
                    Text("Starting scan...")
                        .font(.caption)
                case .discovering(let location):
                    Text("Discovering in \(location)...")
                        .font(.caption)
                case .parsing(let current, let total, let name):
                    Text("Parsing: \(name)")
                        .font(.caption)
                        .lineLimit(1)
                    ProgressView(value: Double(current), total: Double(total))
                    Text("\(current) of \(total)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                case .completed(let count, let duration):
                    Text("Found \(count) projects in \(String(format: "%.1f", duration))s")
                        .font(.caption)
                case .failed(let error):
                    Text("Error: \(error.localizedDescription)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal)
        }
    }

    private func filterIcon(for filter: ProjectFilter) -> some View {
        let iconName: String
        switch filter {
        case .all:
            iconName = "music.note.list"
        case .favorites:
            iconName = "star.fill"
        case .recentlyOpened:
            iconName = "clock.arrow.circlepath"
        case .recentlyModified:
            iconName = "clock"
        case .missingSamples:
            iconName = "exclamationmark.triangle"
        case .highBPM:
            iconName = "hare"
        case .normalBPM:
            iconName = "figure.walk"
        case .lowBPM:
            iconName = "tortoise"
        }
        return Image(systemName: iconName)
    }

    private func volumeIcon(for volume: String) -> String {
        if volume == "Macintosh HD" {
            return "internaldrive"
        } else {
            return "externaldrive"
        }
    }

    private func projectCount(for volume: String) -> Int {
        appState.projects.filter { $0.sourceVolume == volume }.count
    }

    private func tagCount(for tag: String) -> Int {
        appState.projects.filter { $0.userTags.contains(tag) }.count
    }

    private func pluginCount(for plugin: String) -> Int {
        appState.projects.filter { $0.plugins.contains(plugin) }.count
    }

    private func keyCount(for key: String) -> Int {
        appState.projects.filter { $0.musicalKeys.contains(key) }.count
    }

    private func folderCount(for folder: String) -> Int {
        appState.projectsByFolder[folder]?.count ?? 0
    }

    private func displayKey(_ key: String) -> String {
        if useCamelotNotation, let camelot = CamelotConverter.toCamelot(key) {
            return camelot
        }
        return key
    }

    private var appTitle: String {
        #if DEBUG
        return "abledex (dev)"
        #else
        return "abledex"
        #endif
    }

    private func statusCount(for status: CompletionStatus) -> Int {
        appState.projects.filter { $0.completionStatus == status }.count
    }

    private func statusColor(for status: CompletionStatus) -> Color {
        switch status {
        case .none: return .secondary
        case .idea: return .yellow
        case .inProgress: return .blue
        case .mixing: return .purple
        case .done: return .green
        }
    }

    private func colorForLabel(_ label: ColorLabel) -> Color {
        switch label {
        case .none: return .clear
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .gray: return .gray
        }
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.prompt = "Add Folder"

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                try? await appState.addLocation(path: url.path)
            }
        }
    }
}
