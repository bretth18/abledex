//
//  SidebarView.swift
//  abledex
//
//  Created by Brett Henderson on 12/14/25.
//

import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.theme) private var theme
    @AppStorage("useCamelotNotation") private var useCamelotNotation = false
    @State private var isLibraryExpanded = true
    @State private var expandedSections: Set<SidebarSection> = [.musicProjects, .status, .tags, .colors, .locations]
    @State private var sectionOrder: [SidebarSection] = SidebarOrderStorage.order
    @State private var showNewCollectionSheet = false
    @State private var newCollectionName = ""
    @State private var newCollectionKind: CollectionKind = .ep
    @State private var collectionToRename: CollectionRecord?
    @State private var renameText = ""

    var body: some View {
        @Bindable var state = appState

        List(selection: $state.selectedFilter) {
            
            HStack(alignment: .center) {
                Image(.logopdf)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                Text(appTitle)
                    .font(.largeTitle.bold())
                    .padding(.vertical, 4)
            }

            // Library section (always first)
            librarySection

            // Dynamic sections based on stored order
            ForEach(sectionOrder) { section in
                sectionView(for: section)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(theme.usesCustomBackground ? .hidden : .automatic)
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            // Fires on EVERY defaults write (sort persistence, column autosave...) —
            // only touch state when the order actually changed to avoid full rebuilds.
            let newOrder = SidebarOrderStorage.order
            if sectionOrder != newOrder {
                sectionOrder = newOrder
            }
        }
        .sheet(isPresented: $showNewCollectionSheet) {
            newCollectionSheet
        }
        .alert(
            "Rename Music Project",
            isPresented: Binding(
                get: { collectionToRename != nil },
                set: { if !$0 { collectionToRename = nil } }
            ),
            presenting: collectionToRename
        ) { collection in
            TextField("Name", text: $renameText)
            Button("Rename") {
                var updated = collection
                updated.name = renameText.trimmingCharacters(in: .whitespaces)
                guard !updated.name.isEmpty else { return }
                Task {
                    do {
                        try await appState.updateCollection(updated)
                    } catch {
                        appState.reportError("Failed to Rename Music Project", error)
                    }
                }
            }
            .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Music Projects Section

    @ViewBuilder
    private var musicProjectsSection: some View {
        Section(isExpanded: expansionBinding(for: .musicProjects)) {
            ForEach(appState.collections) { collection in
                musicProjectRow(collection)
            }

            Button {
                newCollectionName = ""
                newCollectionKind = .ep
                showNewCollectionSheet = true
            } label: {
                Label("New Music Project...", systemImage: "plus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        } header: {
            Text("Music Projects")
        }
    }

    private func musicProjectRow(_ collection: CollectionRecord) -> some View {
        let progress = appState.collectionProgress(collection)
        return Button {
            appState.toggleSectionFilter(\.selectedCollectionFilter, collection.id)
        } label: {
            Label {
                HStack {
                    Text(collection.name)
                    Spacer()
                    Text("\(progress.done)/\(progress.total)")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .monospacedDigit()
                }
            } icon: {
                Image(systemName: collection.status == .released ? "checkmark.seal.fill" : collection.kind.icon)
                    .foregroundStyle(.tint)
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(
            appState.selectedCollectionFilter == collection.id
                ? theme.surfaceSelected
                : Color.clear
        )
        .contextMenu {
            Button("Rename...") {
                renameText = collection.name
                collectionToRename = collection
            }

            Menu("Set Status") {
                ForEach(CollectionStatus.allCases, id: \.self) { status in
                    Button {
                        var updated = collection
                        updated.status = status
                        Task {
                            do {
                                try await appState.updateCollection(updated)
                            } catch {
                                appState.reportError("Failed to Update Music Project", error)
                            }
                        }
                    } label: {
                        if collection.status == status {
                            Label(status.label, systemImage: "checkmark")
                        } else {
                            Label(status.label, systemImage: status.icon)
                        }
                    }
                }
            }

            Menu("Set Type") {
                ForEach(CollectionKind.allCases, id: \.self) { kind in
                    Button {
                        var updated = collection
                        updated.kind = kind
                        Task {
                            do {
                                try await appState.updateCollection(updated)
                            } catch {
                                appState.reportError("Failed to Update Music Project", error)
                            }
                        }
                    } label: {
                        if collection.kind == kind {
                            Label(kind.label, systemImage: "checkmark")
                        } else {
                            Label(kind.label, systemImage: kind.icon)
                        }
                    }
                }
            }

            Divider()

            Button("Delete Music Project", role: .destructive) {
                Task {
                    do {
                        try await appState.deleteCollection(collection)
                    } catch {
                        appState.reportError("Failed to Delete Music Project", error)
                    }
                }
            }
        }
    }

    private var newCollectionSheet: some View {
        VStack(spacing: 16) {
            Text("New Music Project")
                .font(.headline)

            TextField("Name (e.g. Summer EP)", text: $newCollectionName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)

            Picker("Type", selection: $newCollectionKind) {
                ForEach(CollectionKind.allCases, id: \.self) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()

            HStack {
                Button("Cancel") {
                    showNewCollectionSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    let name = newCollectionName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    Task {
                        do {
                            let collection = try await appState.createCollection(name: name, kind: newCollectionKind)
                            appState.selectedCollectionFilter = collection.id
                        } catch {
                            appState.reportError("Failed to Create Music Project", error)
                        }
                        showNewCollectionSheet = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newCollectionName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }

    // MARK: - Library Section (Always First)

    @ViewBuilder
    private var librarySection: some View {
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
                        ? theme.surfaceSelected
                        : Color.clear
                )
            }
        } header: {
            Text("Library")
        }
    }

    // MARK: - Dynamic Section Router

    @ViewBuilder
    private func sectionView(for section: SidebarSection) -> some View {
        switch section {
        case .musicProjects:
            musicProjectsSection
        case .status:
            statusSection
        case .colors:
            colorsSection
        case .plugins:
            pluginsSection
        case .keys:
            keysSection
        case .folders:
            foldersSection
        case .tags:
            tagsSection
        case .volumes:
            volumesSection
        case .locations:
            locationsSection
        }
    }

    // MARK: - Status Section

    @ViewBuilder
    private var statusSection: some View {
        Section(isExpanded: expansionBinding(for: .status)) {
            ForEach(CompletionStatus.allCases, id: \.self) { status in
                Button {
                    appState.toggleSectionFilter(\.selectedStatusFilter, status)
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
                            .foregroundStyle(theme.statusColor(for: status))
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    appState.selectedStatusFilter == status
                        ? theme.surfaceSelected
                        : Color.clear
                )
            }
        } header: {
            Text("Status")
        }
    }

    // MARK: - Colors Section

    @ViewBuilder
    private var colorsSection: some View {
        Section(isExpanded: expansionBinding(for: .colors)) {
            ForEach(ColorLabel.allCases.filter { $0 != .none }, id: \.self) { label in
                let count = appState.colorLabelCount(for: label)
                if count > 0 {
                    Button {
                        appState.toggleSectionFilter(\.selectedColorLabelFilter, label)
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
                                .foregroundStyle(theme.colorLabel(for: label))
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        appState.selectedColorLabelFilter == label
                            ? theme.surfaceSelected
                            : Color.clear
                    )
                }
            }
        } header: {
            Text("Colors")
        }
    }

    // MARK: - Plugins Section

    @ViewBuilder
    private var pluginsSection: some View {
        if !appState.uniquePlugins.isEmpty {
            Section(isExpanded: expansionBinding(for: .plugins)) {
                ForEach(appState.uniquePlugins.prefix(20), id: \.self) { plugin in
                    Button {
                        appState.toggleSectionFilter(\.selectedPluginFilter, plugin)
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
                            ? theme.surfaceSelected
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
    }

    // MARK: - Keys Section

    @ViewBuilder
    private var keysSection: some View {
        if !appState.uniqueKeys.isEmpty {
            Section(isExpanded: expansionBinding(for: .keys)) {
                ForEach(appState.uniqueKeys, id: \.self) { key in
                    Button {
                        appState.toggleSectionFilter(\.selectedKeyFilter, key)
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
                            ? theme.surfaceSelected
                            : Color.clear
                    )
                }
            } header: {
                Text("Keys")
            }
        }
    }

    // MARK: - Folders Section

    @ViewBuilder
    private var foldersSection: some View {
        if !appState.uniqueFolders.isEmpty {
            Section(isExpanded: expansionBinding(for: .folders)) {
                ForEach(foldersWithMultipleVersions.prefix(20), id: \.self) { folder in
                    Button {
                        appState.toggleSectionFilter(\.selectedFolderFilter, folder)
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
                            ? theme.surfaceSelected
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
    }

    // MARK: - Tags Section

    @ViewBuilder
    private var tagsSection: some View {
        if !appState.uniqueTags.isEmpty {
            Section(isExpanded: expansionBinding(for: .tags)) {
                ForEach(appState.uniqueTags, id: \.self) { tag in
                    Button {
                        appState.toggleSectionFilter(\.selectedTagFilter, tag)
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
                            ? theme.surfaceSelected
                            : Color.clear
                    )
                }
            } header: {
                Text("Tags")
            }
        }
    }

    // MARK: - Volumes Section

    @ViewBuilder
    private var volumesSection: some View {
        if !appState.uniqueVolumes.isEmpty {
            Section(isExpanded: expansionBinding(for: .volumes)) {
                ForEach(appState.uniqueVolumes, id: \.self) { volume in
                    Button {
                        appState.toggleSectionFilter(\.selectedVolumeFilter, volume)
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
                            ? theme.surfaceSelected
                            : Color.clear
                    )
                }
            } header: {
                Text("Volumes")
            }
        }
    }

    // MARK: - Locations Section

    @ViewBuilder
    private var locationsSection: some View {
        Section(isExpanded: expansionBinding(for: .locations)) {
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
                    Button("Scan Location") {
                        Task {
                            await appState.startLocationScan(location)
                        }
                    }
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

    // MARK: - Bottom Bar

    @ViewBuilder
    private var bottomBar: some View {
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
                if appState.isScanning {
                    appState.cancelScan()
                } else {
                    Task {
                        await appState.startScan()
                    }
                }
            } label: {
                Label(
                    appState.isScanning ? "Stop Scan" : "Scan All Locations",
                    systemImage: appState.isScanning ? "stop.circle" : "arrow.clockwise"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .contextMenu {
                Button("Force Re-scan All") {
                    Task {
                        await appState.startScan(forceReparse: true)
                    }
                }
                .disabled(appState.isScanning)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(theme.usesCustomBackground ? AnyShapeStyle(theme.barBackground) : AnyShapeStyle(.bar))
    }

    // MARK: - Expansion Binding Helper

    private func expansionBinding(for section: SidebarSection) -> Binding<Bool> {
        Binding(
            get: { expandedSections.contains(section) },
            set: { isExpanded in
                if isExpanded {
                    expandedSections.insert(section)
                } else {
                    expandedSections.remove(section)
                }
            }
        )
    }

    // MARK: - Computed Properties

    private var hasActiveFilters: Bool {
        appState.hasActiveFilters
    }

    private var foldersWithMultipleVersions: [String] {
        appState.cachedFoldersWithMultipleVersions
    }

    // MARK: - Helper Functions

    private func clearAllFilters() {
        // AppState's version also clears search + music-project filter and
        // batches everything into one recompute.
        appState.clearAllFilters()
    }

    @ViewBuilder
    private var scanProgressView: some View {
        if let progress = appState.scanProgress {
            VStack(alignment: .leading, spacing: 6) {
                switch progress {
                case .starting:
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Preparing scan...")
                            .font(.caption)
                    }
                case .discovering(let location):
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Finding projects in \(location)...")
                            .font(.caption)
                            .lineLimit(1)
                    }
                case .parsing(let current, let total, let name):
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "doc.text.magnifyingglass")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Text(name)
                                .font(.caption)
                                .fontWeight(.medium)
                                .lineLimit(1)
                        }
                        ProgressView(value: Double(current), total: Double(total))
                            .animation(.easeInOut(duration: 0.2), value: current)
                        HStack {
                            Text("\(current) of \(total) projects")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int((Double(current) / Double(total)) * 100))%")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                    }
                case .completed(let count, let duration):
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Found \(count) projects in \(String(format: "%.1f", duration))s")
                            .font(.caption)
                    }
                case .failed(let error):
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.horizontal)
            .animation(.easeInOut(duration: 0.15), value: appState.scanProgress?.description)
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
        appState.volumeCounts[volume] ?? 0
    }

    private func tagCount(for tag: String) -> Int {
        appState.tagCounts[tag] ?? 0
    }

    private func pluginCount(for plugin: String) -> Int {
        appState.pluginCounts[plugin] ?? 0
    }

    private func keyCount(for key: String) -> Int {
        appState.keyCounts[key] ?? 0
    }

    private func folderCount(for folder: String) -> Int {
        appState.folderCounts[folder] ?? 0
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
        appState.statusCounts[status] ?? 0
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
