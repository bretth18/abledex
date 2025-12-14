import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        List(selection: $state.selectedFilter) {
            
            Text("abledex")
                .font(.largeTitle.bold())
                .padding(.vertical, 4)
                
            
            Section("Library") {
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
            }

            Section("Status") {
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
            }

            if !appState.uniqueVolumes.isEmpty {
                Section("Volumes") {
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
                }
            }

            Section("Locations") {
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
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
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
