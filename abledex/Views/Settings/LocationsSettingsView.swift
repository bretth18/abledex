//
//  LocationsSettingsView.swift
//  abledex
//
//  Created by Brett Henderson on 12/21/25.
//

import SwiftUI

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

#Preview {
    LocationsSettingsView()
}
