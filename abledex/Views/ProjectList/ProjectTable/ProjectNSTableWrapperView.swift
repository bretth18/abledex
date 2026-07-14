//
//  ProjectNSTableWrapperView.swift
//  abledex
//
//  Created by Brett Henderson on 4/4/26.
//

import SwiftUI

/// Drop-in replacement for ProjectTableView using NSTableView for performance comparison.
/// Uses native AppKit cell reuse and row virtualization instead of SwiftUI Table.
struct ProjectNSTableWrapperView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.theme) private var theme
    @State private var showDeleteConfirmation = false
    @State private var showBatchTagSheet = false
    @State private var batchTagInput = ""
    @State private var pendingDeleteIDs: Set<UUID> = []

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 0) {
            if appState.selectedProjectIDs.count > 1 {
                BatchToolbarView(
                    selectedCount: appState.selectedProjectIDs.count,
                    showDeleteConfirmation: $showDeleteConfirmation,
                    showBatchTagSheet: $showBatchTagSheet,
                    onSetStatus: { status in
                        Task { try? await appState.batchSetStatus(status) }
                    },
                    onFavoriteAll: {
                        Task { try? await appState.batchToggleFavorite(true) }
                    },
                    onUnfavoriteAll: {
                        Task { try? await appState.batchToggleFavorite(false) }
                    },
                    theme: theme
                )
            }

            ProjectNSTableView(
                projects: appState.filteredProjects,
                selection: appState.selectedProjectIDs,
                sortColumn: appState.sortColumn,
                sortAscending: appState.sortAscending,
                alternatesRowBackgrounds: !theme.usesCustomBackground,
                onSelectionChanged: { ids in
                    appState.selectedProjectIDs = ids
                },
                onFavoriteToggle: { project in
                    Task { try? await appState.toggleFavorite(project) }
                },
                onOpenProject: { project in
                    appState.openProject(project)
                },
                onRevealProject: { project in
                    appState.revealProject(project)
                },
                onDeleteProjects: { ids in
                    pendingDeleteIDs = ids
                    showDeleteConfirmation = true
                },
                onSetStatus: { project, status in
                    Task { try? await appState.updateProjectStatus(project, status: status) }
                },
                onRescanProject: { project in
                    Task { await appState.rescanProject(project) }
                },
                theme: theme
            )
            .onDeleteCommand {
                if !appState.selectedProjectIDs.isEmpty {
                    pendingDeleteIDs = appState.selectedProjectIDs
                    showDeleteConfirmation = true
                }
            }
            .onKeyPress(.return) {
                if let project = appState.selectedProject {
                    appState.openProject(project)
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.space) {
                if let project = appState.selectedProject {
                    appState.revealProject(project)
                    return .handled
                }
                return .ignored
            }
        }
        .confirmationDialog(
            "Remove \(pendingDeleteIDs.count) project\(pendingDeleteIDs.count == 1 ? "" : "s") from library?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task {
                    if pendingDeleteIDs == appState.selectedProjectIDs {
                        try? await appState.deleteSelectedProjects()
                    } else {
                        for id in pendingDeleteIDs {
                            if let project = appState.projects.first(where: { $0.id == id }) {
                                try? await appState.deleteProject(project)
                            }
                        }
                    }
                    pendingDeleteIDs = []
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteIDs = []
            }
        } message: {
            Text("This only removes the projects from Abledex's index. The files will not be deleted from disk.")
        }
        .sheet(isPresented: $showBatchTagSheet) {
            BatchTagSheetView(
                selectedCount: appState.selectedProjectIDs.count,
                tagInput: $batchTagInput,
                isPresented: $showBatchTagSheet,
                onAdd: { tag in
                    Task { try? await appState.batchAddTag(tag) }
                }
            )
        }
    }
}
