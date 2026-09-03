//
//  SidebarView.swift
//  abledex
//
//  Created by Brett Henderson on 12/14/25.
//

import SwiftUI
import AppKit

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.theme) private var theme
    @AppStorage("useCamelotNotation") private var useCamelotNotation = false
    @State private var isLibraryExpanded = true
    @State private var expandedSections: Set<SidebarSection> = [.musicProjects, .status, .tags, .colors, .locations]
    @State private var sectionOrder: [SidebarSection] = SidebarOrderStorage.order

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

            librarySection

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
            // Fires on every defaults write (sort persistence, column autosave),
            // so only touch state when the order actually changed.
            let newOrder = SidebarOrderStorage.order
            if sectionOrder != newOrder {
                sectionOrder = newOrder
            }
        }
    }

    // MARK: - Library

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
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: filter.icon)
                }
                .tag(filter)
            }

            if appState.duplicatesCount > 0 {
                Button {
                    appState.showDuplicatesOnly.toggle()
                } label: {
                    Label {
                        HStack {
                            Text("Duplicates")
                            Spacer()
                            Text("\(appState.duplicatesCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(.red)
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(appState.showDuplicatesOnly ? theme.surfaceSelected : Color.clear)
            }
        } header: {
            Text("Library")
        }
    }

    // MARK: - Section Router

    @ViewBuilder
    private func sectionView(for section: SidebarSection) -> some View {
        switch section {
        case .musicProjects:
            MusicProjectsSection(expandedSections: $expandedSections)

        case .status:
            SidebarFilterSection(
                title: "Status",
                section: .status,
                values: CompletionStatus.allCases,
                filter: \.selectedStatusFilter,
                count: { appState.statusCounts[$0] ?? 0 },
                row: { SidebarFilterRow($0.label, icon: $0.icon, tint: theme.statusColor(for: $0)) },
                expandedSections: $expandedSections
            )

        case .colors:
            SidebarFilterSection(
                title: "Colors",
                section: .colors,
                values: ColorLabel.allCases.filter { $0 != .none },
                filter: \.selectedColorLabelFilter,
                count: { appState.colorLabelCounts[$0] ?? 0 },
                row: { SidebarFilterRow($0.label, icon: "circle.fill", tint: theme.colorLabel(for: $0)) },
                hidesEmpty: true,
                expandedSections: $expandedSections
            )

        case .plugins:
            SidebarFilterSection(
                title: "Plugins",
                section: .plugins,
                values: appState.uniquePlugins,
                filter: \.selectedPluginFilter,
                count: { appState.pluginCounts[$0] ?? 0 },
                row: { SidebarFilterRow($0, icon: "puzzlepiece.extension", tint: .orange) },
                visibleLimit: 20,
                expandedSections: $expandedSections
            )

        case .keys:
            SidebarFilterSection(
                title: "Keys",
                section: .keys,
                values: appState.uniqueKeys,
                filter: \.selectedKeyFilter,
                count: { appState.keyCounts[$0] ?? 0 },
                row: { SidebarFilterRow(displayKey($0), icon: "music.note", tint: .pink) },
                expandedSections: $expandedSections
            )

        case .folders:
            SidebarFilterSection(
                title: "Project Folders",
                section: .folders,
                values: appState.cachedFoldersWithMultipleVersions,
                filter: \.selectedFolderFilter,
                count: { appState.folderCounts[$0] ?? 0 },
                row: { SidebarFilterRow($0, icon: "folder", tint: .cyan) },
                visibleLimit: 20,
                expandedSections: $expandedSections
            )

        case .tags:
            SidebarFilterSection(
                title: "Tags",
                section: .tags,
                values: appState.uniqueTags,
                filter: \.selectedTagFilter,
                count: { appState.tagCounts[$0] ?? 0 },
                row: { SidebarFilterRow($0, icon: "tag", tint: theme.accent) },
                expandedSections: $expandedSections
            )

        case .volumes:
            SidebarFilterSection(
                title: "Volumes",
                section: .volumes,
                values: appState.uniqueVolumes,
                filter: \.selectedVolumeFilter,
                count: { appState.volumeCounts[$0] ?? 0 },
                row: { SidebarFilterRow($0, icon: $0 == "Macintosh HD" ? "internaldrive" : "externaldrive") },
                expandedSections: $expandedSections
            )

        case .locations:
            locationsSection
        }
    }

    // MARK: - Locations

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
                        Task { await appState.startLocationScan(location) }
                    }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: location.path)
                    }
                    Divider()
                    Button("Remove Location", role: .destructive) {
                        Task { try? await appState.removeLocation(id: location.id) }
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
            if appState.hasActiveFilters {
                HStack {
                    Text("Filters active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") {
                        appState.clearAllFilters()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
                .padding(.horizontal)
            }

            if appState.isScanning, let progress = appState.scanProgress {
                ScanProgressView(progress: progress)
                    .animation(.easeInOut(duration: 0.15), value: progress.description)
            }

            Button {
                if appState.isScanning {
                    appState.cancelScan()
                } else {
                    Task { await appState.startScan() }
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
                    Task { await appState.startScan(forceReparse: true) }
                }
                .disabled(appState.isScanning)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(theme.usesCustomBackground ? AnyShapeStyle(theme.barBackground) : AnyShapeStyle(.bar))
    }

    // MARK: - Helpers

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

    private func displayKey(_ key: String) -> String {
        useCamelotNotation ? (CamelotConverter.toCamelot(key) ?? key) : key
    }

    private var appTitle: String {
        #if DEBUG
        "abledex (dev)"
        #else
        "abledex"
        #endif
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.prompt = "Add Folder"

        if panel.runModal() == .OK, let url = panel.url {
            Task { try? await appState.addLocation(path: url.path) }
        }
    }
}
