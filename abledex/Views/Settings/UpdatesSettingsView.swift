//
//  UpdatesSettingsView.swift
//  abledex
//
//  Created by Brett Henderson on 12/21/25.
//

import SwiftUI

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

#Preview {
    UpdatesSettingsView()
}
