//
//  GeneralSettingsView.swift
//  abledex
//
//  Created by Brett Henderson on 12/21/25.
//

import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage("autoScanOnLaunch") private var autoScanOnLaunch = true
    @AppStorage("scanExternalVolumes") private var scanExternalVolumes = true
    @AppStorage("showMissingSamplesWarning") private var showMissingSamplesWarning = true
    @AppStorage("useCamelotNotation") private var useCamelotNotation = false
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        @Bindable var tm = themeManager

        Form {
            Section {
                Picker("Theme", selection: $tm.selectedThemeName) {
                    ForEach(ThemeName.allCases) { name in
                        Text(name.rawValue).tag(name)
                    }
                }
                .pickerStyle(.segmented)

                Text("System uses macOS colors. Studio is a high-contrast dark theme with Ableton orange accent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Appearance")
            }

            Section {
                Toggle("Scan on launch", isOn: $autoScanOnLaunch)
                Toggle("Include external volumes", isOn: $scanExternalVolumes)
                Toggle("Show missing samples warnings", isOn: $showMissingSamplesWarning)
            } header: {
                Text("Scanning")
            }

            Section {
                Toggle("Use camelot notation for keys", isOn: $useCamelotNotation)
                Text("Display musical keys as Camelot wheel codes (e.g., 8A for A Minor)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Display")
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

#Preview {
    GeneralSettingsView()
}
