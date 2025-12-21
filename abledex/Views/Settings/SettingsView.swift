//
//  SettingsView.swift
//  abledex
//
//  Created by Brett Henderson on 12/14/25.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            LocationsSettingsView()
                .environment(appState)
                .tabItem {
                    Label("Locations", systemImage: "folder")
                }

            UpdatesSettingsView()
                .tabItem {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                }
            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 400)
    }
}
