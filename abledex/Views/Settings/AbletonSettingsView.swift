//
//  AbletonSettingsView.swift
//  abledex
//

import SwiftUI

/// Lists the installed copies of Live and which one opens projects.
struct AbletonSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var installs: [AbletonInstall] = []
    @State private var defaultPath: String? = AbletonPreference.alwaysOpenWithPath
    @State private var isLoading = true

    var body: some View {
        Form {
            Section {
                if isLoading {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("Looking for Ableton Live...")
                            .foregroundStyle(.secondary)
                    }
                } else if installs.isEmpty {
                    Text("No copy of Ableton Live was found in /Applications.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Open projects with", selection: choiceBinding) {
                        Text("Ask every time").tag(String?.none)
                        Divider()
                        ForEach(installs) { install in
                            Text(install.isBeta ? "\(install.displayName) (Beta)" : install.displayName)
                                .tag(String?.some(install.id))
                        }
                    }

                    if installs.count == 1 {
                        Text("Only one version is installed, so abledex opens projects with it directly.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if defaultPath == nil {
                        Text("Several versions are installed. They share a bundle identifier, so macOS cannot tell them apart on its own.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Opening Projects")
            }

            if !installs.isEmpty {
                Section {
                    ForEach(installs) { install in
                        HStack(spacing: 10) {
                            AppIconView(url: install.url)
                                .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(install.displayName)
                                    if install.isBeta {
                                        Text("BETA")
                                            .font(.system(size: 9, weight: .bold))
                                            .themedBadge(.tinted(.orange))
                                    }
                                }
                                Text(install.url.path)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            if let build = install.build {
                                Text(build)
                                    .font(.caption2)
                                    .monospaced()
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("^[\(installs.count) Version](inflect: true) Installed")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            await reload()
        }
    }

    private var choiceBinding: Binding<String?> {
        Binding(
            get: { defaultPath },
            set: { newValue in
                defaultPath = newValue
                AbletonPreference.alwaysOpenWithPath = newValue
            }
        )
    }

    private func reload() async {
        installs = await AbletonInstallFinder.findInstalls()
        appState.abletonInstalls = installs
        // A remembered install that has since been deleted would silently fall
        // back to asking; reflect that in the picker rather than showing a
        // selection that no longer exists.
        if let path = defaultPath, !installs.contains(where: { $0.id == path }) {
            defaultPath = nil
            AbletonPreference.clear()
        }
        isLoading = false
    }
}
