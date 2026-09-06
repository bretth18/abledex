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
            Button(title(for: install)) {
                for project in projects {
                    appState.openProject(project, using: install)
                }
            }
        }
    }

    private func title(for install: AbletonInstall) -> String {
        var title = install.isBeta ? "\(install.displayName) (Beta)" : install.displayName
        if AbletonPreference.alwaysOpenWithPath == install.id {
            title += " (Default)"
        }
        return title
    }
}
