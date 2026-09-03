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
    /// Collections open on their release page; this switches back to the table.
    @State private var showsCollectionTable = false

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } content: {
            VStack(spacing: 0) {
                if let collection = activeCollection, !showsCollectionTable {
                    CollectionDetailView(collection: collection)
                } else if appState.useNSTableView {
                    ProjectNSTableWrapperView()
                } else {
                    ProjectTableView()
                }
            }
            .onChange(of: appState.selectedCollectionFilter) {
                // A newly opened collection always lands on its release page.
                showsCollectionTable = false
            }
            .navigationSplitViewColumnWidth(min: 400, ideal: 600)
                .navigationTitle(navigationTitle)
                .navigationSubtitle("^[\(appState.filteredProjects.count) project](inflect: true)")
                .searchable(text: $state.searchQuery, prompt: "Search projects, plugins, tags...")
                .toolbar {
                    ToolbarItemGroup {
                        #if DEBUG
                        // A/B performance toggle, developer-only
                        Button {
                            appState.useNSTableView.toggle()
                        } label: {
                            Label(
                                appState.useNSTableView ? "NSTableView" : "SwiftUI Table",
                                systemImage: appState.useNSTableView ? "tablecells" : "tablecells.badge.ellipsis"
                            )
                        }
                        .help(appState.useNSTableView ? "Using NSTableView (AppKit). Click to switch to SwiftUI." : "Using SwiftUI Table. Click to switch to NSTableView (AppKit).")
                        #endif

                        if activeCollection != nil {
                            Picker("View", selection: $showsCollectionTable) {
                                Image(systemName: "list.number").tag(false)
                                Image(systemName: "tablecells").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .help(showsCollectionTable ? "Showing the table" : "Showing the release page")
                        }

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
        .sheet(item: $state.pendingOpen) { pending in
            OpenWithAbletonSheet(pending: pending)
        }
        .alert(
            appState.activeError?.title ?? "Something Went Wrong",
            isPresented: Binding(
                get: { appState.activeError != nil },
                set: { if !$0 { appState.activeError = nil } }
            ),
            presenting: appState.activeError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
    }

    private var activeCollection: CollectionRecord? {
        guard let id = appState.selectedCollectionFilter else { return nil }
        return appState.collections.first { $0.id == id }
    }

    private var navigationTitle: String {
        if let collection = activeCollection {
            return collection.name
        }
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
