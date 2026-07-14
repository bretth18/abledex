//
//  ContentView.swift
//  abledex
//
//  Created by Brett Henderson on 12/14/25.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.theme) private var theme
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showStatistics = false

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } content: {
            Group {
                if appState.useNSTableView {
                    ProjectNSTableWrapperView()
                } else {
                    ProjectTableView()
                }
            }
            .navigationSplitViewColumnWidth(min: 400, ideal: 600)
                .navigationTitle(navigationTitle)
                .navigationSubtitle("\(appState.filteredProjects.count) projects")
                .searchable(text: $state.searchQuery, prompt: "Search projects, plugins, tags...")
                .toolbar {
                    ToolbarItemGroup {
                        // A/B performance toggle
                        Button {
                            appState.useNSTableView.toggle()
                        } label: {
                            Label(
                                appState.useNSTableView ? "NSTableView" : "SwiftUI Table",
                                systemImage: appState.useNSTableView ? "tablecells" : "tablecells.badge.ellipsis"
                            )
                        }
                        .help(appState.useNSTableView ? "Using NSTableView (AppKit) — click to switch to SwiftUI" : "Using SwiftUI Table — click to switch to NSTableView (AppKit)")

                        Button {
                            showStatistics = true
                        } label: {
                            Label("Statistics", systemImage: "chart.pie")
                        }

                        sortMenu
                    }
                }
        } detail: {
            if let project = appState.selectedProject {
                ProjectDetailView(project: project)
                    .navigationSplitViewColumnWidth(min: 300, ideal: 350)
            } else {
                ProjectDetailEmptyView()
                    .navigationSplitViewColumnWidth(min: 200, ideal: 250)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showStatistics) {
            StatisticsView()
        }
    }

    private var navigationTitle: String {
        if let tagFilter = appState.selectedTagFilter {
            return "Tag: \(tagFilter)"
        }
        if let pluginFilter = appState.selectedPluginFilter {
            return "Plugin: \(pluginFilter)"
        }
        if let volumeFilter = appState.selectedVolumeFilter {
            return volumeFilter
        }
        if let statusFilter = appState.selectedStatusFilter {
            return statusFilter.label
        }
        return appState.selectedFilter.rawValue
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SortColumn.allCases, id: \.self) { column in
                Button {
                    if appState.sortColumn == column {
                        appState.sortAscending.toggle()
                    } else {
                        appState.sortColumn = column
                        appState.sortAscending = column == .name
                    }
                } label: {
                    HStack {
                        Text(column.rawValue)
                        if appState.sortColumn == column {
                            Image(systemName: appState.sortAscending ? "chevron.up" : "chevron.down")
                        }
                    }
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState(database: try! .empty()))
}
