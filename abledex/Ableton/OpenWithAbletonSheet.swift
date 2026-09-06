//
//  OpenWithAbletonSheet.swift
//  abledex
//

import SwiftUI

/// Asks which Ableton Live install should open a project, when more than one
/// is present. Offers to remember the choice for future opens.
struct OpenWithAbletonSheet: View {
    let pending: AppState.PendingOpen

    @Environment(AppState.self) private var appState
    @Environment(\.theme) private var theme
    @State private var selectedID: AbletonInstall.ID?
    @State private var alwaysUse = false

    private var projectVersion: String? { pending.project.abletonVersion }
    private var openCount: Int { 1 + pending.additionalProjects.count }

    private var selection: AbletonInstall? {
        pending.installs.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                if openCount > 1 {
                    Text("Open ^[\(openCount) Projects](inflect: true) With")
                        .font(.headline)
                } else {
                    Text("Open “\(pending.project.name)” With")
                        .font(.headline)
                        .lineLimit(1)
                    if let projectVersion {
                        Text("Saved in Live \(projectVersion)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.bottom, 16)

            Picker("Version", selection: $selectedID) {
                ForEach(pending.installs) { install in
                    row(install).tag(Optional(install.id))
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Toggle("Always open with this version", isOn: $alwaysUse)
                .padding(.top, 20)
            Text("You can change this in Settings > Ableton.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 20)

            HStack {
                Spacer()
                Button("Cancel") {
                    appState.cancelPendingOpen()
                }
                .keyboardShortcut(.cancelAction)

                Button("Open") {
                    guard let selection else { return }
                    appState.completePendingOpen(with: selection, remember: alwaysUse)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil)
            }
            .padding(.top, 20)
        }
        .padding(20)
        .frame(width: 420)
        .background(theme.usesCustomBackground ? theme.background : nil)
        .onAppear {
            // Prefer the release matching the version the set was saved with,
            // then any matching beta, then the newest install that can open it.
            // Installs are ordered releases first, newest first.
            selectedID = (
                pending.installs.first { matchesSet($0) && !$0.isBeta }
                ?? pending.installs.first(where: matchesSet)
                ?? pending.installs.first { $0.canOpenProject(savedWith: projectVersion) }
                ?? pending.installs.first
            )?.id
        }
    }

    private func row(_ install: AbletonInstall) -> some View {
        HStack(spacing: 10) {
            AppIconView(url: install.url)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(install.isBeta ? "\(install.displayName) (Beta)" : install.displayName)
                if !install.canOpenProject(savedWith: projectVersion) {
                    Text("Older than this set")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if let detail = detail(for: install) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// A second line only when it tells the installs apart: which one the set
    /// was saved with when they differ, or where it lives when folders differ.
    private func detail(for install: AbletonInstall) -> String? {
        let installs = pending.installs
        if matchesSet(install), !installs.allSatisfy(matchesSet) {
            return "Same version as this set"
        }
        let folders = Set(installs.map { $0.url.deletingLastPathComponent() })
        if folders.count > 1 {
            return install.url.deletingLastPathComponent().path(percentEncoded: false)
        }
        return nil
    }

    private func matchesSet(_ install: AbletonInstall) -> Bool {
        install.majorMinor != nil && install.majorMinor == AbletonInstall.majorMinor(of: projectVersion)
    }
}

/// The Finder icon for an application bundle.
struct AppIconView: View {
    let url: URL

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .interpolation(.high)
    }
}
