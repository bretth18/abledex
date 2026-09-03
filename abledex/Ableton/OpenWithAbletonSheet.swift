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
    @State private var selection: AbletonInstall?
    @State private var alwaysUse = false

    private var projectVersion: String? { pending.project.abletonVersion }

    private var openCount: Int { 1 + pending.additionalProjects.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(pending.installs) { install in
                        installRow(install)
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 260)

            Divider()
            footer
        }
        .frame(width: 420)
        .background(theme.usesCustomBackground ? theme.background : nil)
        .onAppear {
            // Preselect the install that matches the version the set was saved
            // with; otherwise the newest one that can open it at all.
            let matchesSet = { (install: AbletonInstall) in
                install.majorMinor != nil && install.majorMinor == AbletonInstall.majorMinor(of: projectVersion)
            }
            // installs are already ordered releases-first, newest-first.
            selection = pending.installs.first { matchesSet($0) && !$0.isBeta }
                ?? pending.installs.first(where: matchesSet)
                ?? pending.installs.first { $0.canOpenProject(savedWith: projectVersion) }
                ?? pending.installs.first
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(openCount > 1 ? "Open \(openCount) Projects With" : "Open With")
                .font(.headline)

            if openCount > 1 {
                Text("You have several versions of Live installed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 4) {
                    Text(pending.project.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if let projectVersion {
                        Text("· saved in Live \(projectVersion)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private func installRow(_ install: AbletonInstall) -> some View {
        let isSelected = selection == install
        let matchesProject = install.majorMinor != nil
            && install.majorMinor == AbletonInstall.majorMinor(of: projectVersion)
        let isOlder = !install.canOpenProject(savedWith: projectVersion)

        return Button {
            selection = install
        } label: {
            HStack(spacing: 12) {
                AppIconView(url: install.url)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(install.displayName)
                            .fontWeight(isSelected ? .semibold : .regular)
                        if install.isBeta {
                            Text("BETA")
                                .font(.system(size: 9, weight: .bold))
                                .themedBadge(.tinted(.orange))
                        }
                        if matchesProject {
                            Text("MATCHES SET")
                                .font(.system(size: 9, weight: .bold))
                                .themedBadge(.tinted(.green))
                        }
                    }

                    if isOlder, let projectVersion {
                        Label("Older than the set (saved in \(projectVersion))", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else {
                        Text(install.url.path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? theme.accentSubtle : theme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Always open with this version", isOn: $alwaysUse)
                .font(.callout)

            Text("You can change this later in Settings › Ableton.")
                .font(.caption2)
                .foregroundStyle(.secondary)

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
                .buttonStyle(.borderedProminent)
                .disabled(selection == nil)
            }
        }
        .padding(16)
    }
}

/// The real Finder icon for an application bundle.
struct AppIconView: View {
    let url: URL

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .interpolation(.high)
    }
}
