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
}
