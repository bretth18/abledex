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
            if isLoading {
                Section("Opening Projects") {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Looking for Ableton Live…")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if installs.isEmpty {
                Section("Opening Projects") {
                    Text("Ableton Live is not installed in the Applications folder.")
                        .foregroundStyle(.secondary)
                }
            } else {
                if installs.count > 1 {
                    Section {
                        Picker("Open projects with", selection: choiceBinding) {
                            Text("Ask Every Time").tag(String?.none)
                            Divider()
                            ForEach(installs) { install in
                                Text(name(of: install)).tag(String?.some(install.id))
                            }
                        }
                    } header: {
                        Text("Opening Projects")
                    } footer: {
                        Text("Choosing “Ask Every Time” shows a list of installed versions whenever you open a project.")
                    }
                }

                Section("Installed Versions") {
                    ForEach(installs) { install in
                        HStack(spacing: 10) {
                            AppIconView(url: install.url)
                                .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name(of: install))
                                Text(install.url.path(percentEncoded: false))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            if let build = install.build {
                                Text(build)
                                    .font(.caption)
                                    .monospaced()
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            await reload()
        }
    }

    private func name(of install: AbletonInstall) -> String {
        install.isBeta ? "\(install.displayName) (Beta)" : install.displayName
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
        // A remembered install that has since been deleted falls back to
        // asking; show that instead of a selection that no longer exists.
        if let path = defaultPath, !installs.contains(where: { $0.id == path }) {
            defaultPath = nil
            AbletonPreference.clear()
        }
        isLoading = false
    }
}
