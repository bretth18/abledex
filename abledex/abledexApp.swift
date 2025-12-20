import SwiftUI

@main
struct AbledexApp: App {
    @State private var appState: AppState

    init() {
        do {
            let database = try AppDatabase.live()
            _appState = State(initialValue: AppState(database: database))
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .task {
                    await appState.loadData()
                    appState.startVolumeMonitoring()
                }
                .onDisappear {
                    appState.stopVolumeMonitoring()
                }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    Task {
                        await UpdateService.shared.checkForUpdates()
                        if UpdateService.shared.updateAvailable {
                            showUpdateAlert()
                        } else if UpdateService.shared.errorMessage == nil {
                            showNoUpdateAlert()
                        }
                    }
                }
                .disabled(UpdateService.shared.isChecking)
            }

            CommandGroup(after: .newItem) {
                Button("Scan All Locations") {
                    Task {
                        await appState.startScan()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(appState.isScanning)

                Divider()

                Button("Add Folder...") {
                    selectFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .help) {
                Button("Abledex Help") {
                    // Could open documentation
                }
            }
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(appState)
        }
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
            Task {
                try? await appState.addLocation(path: url.path)
            }
        }
    }

    private func showUpdateAlert() {
        let updateService = UpdateService.shared
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "Version \(updateService.latestVersion ?? "unknown") is available. You are currently running version \(updateService.currentVersion)."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download Update")
        alert.addButton(withTitle: "View Release Notes")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            updateService.downloadAndInstallUpdate()
        case .alertSecondButtonReturn:
            updateService.openReleasePage()
        default:
            break
        }
    }

    private func showNoUpdateAlert() {
        let alert = NSAlert()
        alert.messageText = "You're Up to Date"
        alert.informativeText = "Abledex \(UpdateService.shared.currentVersion) is currently the newest version available."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
