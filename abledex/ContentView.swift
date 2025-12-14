import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } content: {
            ProjectTableView()
                .navigationSplitViewColumnWidth(min: 400, ideal: 600)
                .navigationTitle(navigationTitle)
                .searchable(text: $state.searchQuery, prompt: "Search projects...")
                .toolbar {
                    ToolbarItemGroup {
                        sortMenu
                    }
                }
        } detail: {
            if let project = appState.selectedProject {
                ProjectDetailView(project: project)
            } else {
                ProjectDetailEmptyView()
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var navigationTitle: String {
        if let volumeFilter = appState.selectedVolumeFilter {
            return volumeFilter
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
