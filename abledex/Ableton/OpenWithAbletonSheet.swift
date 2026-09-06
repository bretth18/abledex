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
            header
                .padding(20)

            List(pending.installs, selection: $selectedID) { install in
                row(install)
            }
            .listStyle(.bordered)
            .scrollContentBackground(theme.usesCustomBackground ? .hidden : .automatic)
            .frame(height: CGFloat(min(pending.installs.count, 5)) * 48 + 4)
            .padding(.horizontal, 20)

            footer
                .padding(20)
        }
        .frame(width: 440)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(openCount > 1 ? "Open ^[\(openCount) Projects](inflect: true) With" : "Open With")
                .font(.headline)

            if openCount == 1 {
                if let projectVersion {
                    Text("\(pending.project.name) · saved in Live \(projectVersion)")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(pending.project.name)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ install: AbletonInstall) -> some View {
        HStack(spacing: 10) {
            AppIconView(url: install.url)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(install.isBeta ? "\(install.displayName) (Beta)" : install.displayName)
                Text(install.url.deletingLastPathComponent().path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if !install.canOpenProject(savedWith: projectVersion) {
                Label("Older than this set", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if matchesSet(install) {
                Text("Matches set")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .tag(install.id)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Always open with this version", isOn: $alwaysUse)
                Text("Change this later in Settings > Ableton.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
        }
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
