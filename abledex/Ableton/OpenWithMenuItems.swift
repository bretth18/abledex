//
//  OpenWithMenuItems.swift
//  abledex
//

import SwiftUI

/// Menu entries that open the given projects with one specific Live install,
/// bypassing the remembered default for a single open.
struct OpenWithMenuItems: View {
    let projects: [ProjectRecord]
    @Environment(AppState.self) private var appState

    init(project: ProjectRecord) {
        self.projects = [project]
    }

    init(projects: [ProjectRecord]) {
        self.projects = projects
    }

    var body: some View {
        ForEach(appState.abletonInstalls) { install in
            Button {
                for project in projects {
                    appState.openProject(project, using: install)
                }
            } label: {
                Label(
                    install.isBeta ? "\(install.displayName) (Beta)" : install.displayName,
                    systemImage: isDefault(install) ? "checkmark" : "waveform"
                )
            }
        }
    }

    private func isDefault(_ install: AbletonInstall) -> Bool {
        AbletonPreference.alwaysOpenWithPath == install.id
    }
}
