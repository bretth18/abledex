import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            LocationsSettingsView()
                .environment(appState)
                .tabItem {
                    Label("Locations", systemImage: "folder")
                }

            UpdatesSettingsView()
                .tabItem {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                }
            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
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

struct UpdatesSettingsView: View {
    @State private var updateService = UpdateService.shared

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Abledex")
                            .font(.headline)
                        Text("Version \(updateService.currentVersion) (Build \(updateService.currentBuild))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if updateService.isChecking {
                        ProgressView()
                            .scaleEffect(0.7)
                    }

                    Button("Check for Updates") {
                        Task {
                            await updateService.checkForUpdates()
                        }
                    }
                    .disabled(updateService.isChecking)
                }

                if let lastCheck = updateService.lastCheckDate {
                    Text("Last checked: \(lastCheck, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } header: {
                Text("Current Version")
            }

            if updateService.updateAvailable, let latestVersion = updateService.latestVersion {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Version \(latestVersion) Available", systemImage: "arrow.down.circle.fill")
                                .font(.headline)
                                .foregroundStyle(.green)

                            Spacer()
                        }

                        if let notes = updateService.releaseNotes, !notes.isEmpty {
                            Text("Release Notes:")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            ScrollView {
                                Text(notes)
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 100)
                            .padding(8)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }

                        HStack {
                            Button("Download Update") {
                                updateService.downloadAndInstallUpdate()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("View on GitHub") {
                                updateService.openReleasePage()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } header: {
                    Text("Update Available")
                }
            }

            if let error = updateService.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                } header: {
                    Text("Error")
                }
            }

            Section {
                Link(destination: URL(string: "https://github.com/bretth18/abledex/releases")!) {
                    Label("View All Releases on GitHub", systemImage: "link")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AboutSettingsView: View {
    
    var body: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: 4) {
                    Text("abledex")
                        .font(.largeTitle.bold())
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding()
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("© 2025 COMPUTER DATA")
                }
            } header: {
                Text("About")
            }
            
            Section {
                Link("License (MIT)", destination: URL(string: "https://github.com/bretth18/abledex/blob/main/LICENSE")!)
            } header: {
                Text("License")
            }
            
        }
        .formStyle(.grouped)
        .padding()
                
    }
}
