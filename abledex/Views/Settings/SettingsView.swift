import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            LocationsSettingsView()
                .environment(appState)
                .tabItem {
                    Label("Locations", systemImage: "folder")
                }

            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
        }
        .frame(width: 500, height: 400)
    }
}

struct LocationsSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scan Locations")
                .font(.headline)

            Text("Abledex will scan these folders for Ableton Live projects.")
                .font(.callout)
                .foregroundStyle(.secondary)

            List {
                ForEach(appState.locations) { location in
                    HStack {
                        VStack(alignment: .leading) {
                            HStack {
                                Text(location.displayName)
                                if location.isAutoDetected {
                                    Text("Auto")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.quaternary)
                                        .clipShape(Capsule())
                                }
                            }
                            Text(location.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if location.projectCount > 0 {
                            Text("\(location.projectCount) projects")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if !location.isAutoDetected {
                            Button(role: .destructive) {
                                Task {
                                    try? await appState.removeLocation(id: location.id)
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .listStyle(.bordered)

            HStack {
                Button("Add Folder...") {
                    selectFolder()
                }

                Spacer()

                Button("Scan Now") {
                    Task {
                        await appState.startScan()
                    }
                }
                .disabled(appState.isScanning)
            }
        }
        .padding()
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

struct GeneralSettingsView: View {
    @AppStorage("autoScanOnLaunch") private var autoScanOnLaunch = true
    @AppStorage("scanExternalVolumes") private var scanExternalVolumes = true
    @AppStorage("showMissingSamplesWarning") private var showMissingSamplesWarning = true

    var body: some View {
        Form {
            Section {
                Toggle("Scan on launch", isOn: $autoScanOnLaunch)
                Toggle("Include external volumes", isOn: $scanExternalVolumes)
                Toggle("Show missing samples warnings", isOn: $showMissingSamplesWarning)
            } header: {
                Text("Scanning")
            }

            Section {
                Text("Database location:")
                    .foregroundStyle(.secondary)

                let dbPath = FileManager.default
                    .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                    .first?
                    .appendingPathComponent("Abledex/abledex.sqlite")
                    .path ?? "Unknown"

                Text(dbPath)
                    .font(.caption)
                    .textSelection(.enabled)
            } header: {
                Text("Storage")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
