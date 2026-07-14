//
//  abledexApp.swift
//  abledex
//
//  Created by Brett Henderson on 12/14/25.
//

import SwiftUI

@main
struct AbledexApp: App {
    @State private var appState: AppState
    @State private var themeManager = ThemeManager()
    @State private var didRunLaunchTask = false
    private let databaseError: Error?

    init() {
        do {
            let database = try AppDatabase.live()
            _appState = State(initialValue: AppState(database: database))
            databaseError = nil
        } catch {
            // Don't crash at launch on a corrupted DB or full disk — fall back to a
            // temporary in-memory database and surface the error to the user.
            _appState = State(initialValue: AppState(database: try! AppDatabase.empty()))
            databaseError = error
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(themeManager)
                .environment(\.theme, themeManager.current)
                .preferredColorScheme(themeManager.current.preferredColorScheme)
                .tint(themeManager.current.usesCustomBackground ? themeManager.current.accent : nil)
                .windowBackground(themeManager.current.windowBackground)
                .task {
                    // This .task re-runs on every window open — launch work must run once
                    guard !didRunLaunchTask else { return }
                    didRunLaunchTask = true

                    if let databaseError {
                        appState.reportError(
                            "Database Could Not Be Opened",
                            databaseError
                        )
                        return
                    }
                    await appState.loadData()
                    appState.startVolumeMonitoring()

                    if UserDefaults.standard.object(forKey: "autoScanOnLaunch") as? Bool ?? true {
                        await appState.startScan()
                    }
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

                Button("Stop Scan") {
                    appState.cancelScan()
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!appState.isScanning)

                Divider()

                Button("Add Folder...") {
                    selectFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Divider()

                Button("Export Library as CSV...") {
                    do {
                        try ExportService.exportCSV(projects: appState.filteredProjects)
                    } catch {
                        appState.reportError("Export Failed", error)
                    }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(appState.filteredProjects.isEmpty)
            }

            CommandMenu("Project") {
                Button("Open in Ableton Live") {
                    if let project = appState.selectedProject {
                        appState.openProject(project)
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(appState.selectedProject == nil)

                Button("Reveal in Finder") {
                    if let project = appState.selectedProject {
                        appState.revealProject(project)
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(appState.selectedProject == nil)

                Divider()

                Button(appState.selectedProject?.isFavorite == true ? "Remove Favorite" : "Add Favorite") {
                    if let project = appState.selectedProject {
                        Task {
                            do {
                                try await appState.toggleFavorite(project)
                            } catch {
                                appState.reportError("Failed to Update Favorite", error)
                            }
                        }
                    }
                }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(appState.selectedProject == nil)
            }

            CommandGroup(replacing: .help) {
                Link("Abledex Help", destination: URL(string: "https://github.com/bretth18/abledex")!)
            }
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(appState)
                .environment(themeManager)
                .environment(\.theme, themeManager.current)
                .preferredColorScheme(themeManager.current.preferredColorScheme)
                .tint(themeManager.current.usesCustomBackground ? themeManager.current.accent : nil)
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
                do {
                    try await appState.addLocation(path: url.path)
                } catch {
                    appState.reportError("Failed to Add Folder", error)
                }
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
