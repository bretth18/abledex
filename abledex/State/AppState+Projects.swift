//
//  AppState+Projects.swift
//  abledex
//

import Foundation
import AppKit

extension AppState {
    // MARK: - Project Actions

    func openProject(_ project: ProjectRecord) {
        // Judge reachability by the file itself, not the offline flag — volumes
        // mounted outside /Volumes (network shares, secondary APFS volumes) are
        // reachable even when no /Volumes/<name> mount point exists.
        guard FileManager.default.fileExists(atPath: project.alsFilePath) else {
            let message = isVolumeOnline(project)
                ? "\"\(project.name)\" could not be found at \(project.alsFilePath). It may have been moved or deleted — try re-scanning."
                : "\"\(project.name)\" is on \"\(project.sourceVolume)\", which isn't currently mounted. Connect the drive and try again."
            activeError = UserFacingError(title: "Project Not Available", message: message)
            return
        }

        let alsURL = URL(fileURLWithPath: project.alsFilePath)
        let projectID = project.id

        Task {
            do {
                // Async variant — the sync open() can block the main actor while Live launches
                try await NSWorkspace.shared.open(alsURL, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                reportError("Failed to Open Project", error)
                return
            }

            // Track last opened time on the CURRENT record — Live can take many
            // seconds to launch, and saving the click-time snapshot would revert
            // any edits the user made in the meantime.
            guard let current = projects.first(where: { $0.id == projectID }) else { return }
            var updated = current
            updated.lastOpenedAt = Date()
            try? await database.saveProject(updated)
            applyUpdatedProject(updated)
        }
    }

    func revealProject(_ project: ProjectRecord) {
        let folderURL = URL(fileURLWithPath: project.folderPath)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
    }

    func deleteProject(_ project: ProjectRecord) async throws {
        try await database.deleteProject(id: project.id)
        selectedProjectIDs.remove(project.id)
    }

    func deleteSelectedProjects() async throws {
        let idsToDelete = selectedProjectIDs
        try await database.deleteProjects(ids: Array(idsToDelete))
        selectedProjectIDs.removeAll()
    }

    func updateProjectTags(_ project: ProjectRecord, tags: [String]) async throws {
        var updated = project
        updated.userTags = tags
        try await database.saveProject(updated)
        applyUpdatedProject(updated)
    }

    func updateProjectNotes(_ project: ProjectRecord, notes: String) async throws {
        var updated = project
        updated.userNotes = notes
        try await database.saveProject(updated)
        applyUpdatedProject(updated)
    }

    func updateProjectStatus(_ project: ProjectRecord, status: CompletionStatus) async throws {
        var updated = project
        updated.completionStatus = status
        try await database.saveProject(updated)
        applyUpdatedProject(updated)
    }

    func toggleFavorite(_ project: ProjectRecord) async throws {
        var updated = project
        updated.isFavorite = !project.isFavorite
        try await database.saveProject(updated)
        applyUpdatedProject(updated)
    }

    // MARK: - Batch Operations

    /// Saves all mutations in one DB transaction; the projects observation
    /// delivers the new state.
    private func performBatchUpdate(_ mutate: (inout [ProjectRecord]) -> [ProjectRecord]) async throws {
        var mutableProjects = projects
        let updatedRecords = mutate(&mutableProjects)

        guard !updatedRecords.isEmpty else { return }

        try await database.saveProjects(updatedRecords)
    }

    func batchSetStatus(_ status: CompletionStatus) async throws {
        try await performBatchUpdate { projects in
            var updated: [ProjectRecord] = []
            for id in selectedProjectIDs {
                if let index = projects.firstIndex(where: { $0.id == id }) {
                    projects[index].completionStatus = status
                    updated.append(projects[index])
                }
            }
            return updated
        }
    }

    func batchAddTag(_ tag: String) async throws {
        try await performBatchUpdate { projects in
            var updated: [ProjectRecord] = []
            for id in selectedProjectIDs {
                if let index = projects.firstIndex(where: { $0.id == id }) {
                    if !projects[index].userTags.contains(tag) {
                        var tags = projects[index].userTags
                        tags.append(tag)
                        projects[index].userTags = tags
                        updated.append(projects[index])
                    }
                }
            }
            return updated
        }
    }

    func batchRemoveTag(_ tag: String) async throws {
        try await performBatchUpdate { projects in
            var updated: [ProjectRecord] = []
            for id in selectedProjectIDs {
                if let index = projects.firstIndex(where: { $0.id == id }) {
                    var tags = projects[index].userTags
                    tags.removeAll { $0 == tag }
                    projects[index].userTags = tags
                    updated.append(projects[index])
                }
            }
            return updated
        }
    }

    func batchToggleFavorite(_ setFavorite: Bool) async throws {
        try await performBatchUpdate { projects in
            var updated: [ProjectRecord] = []
            for id in selectedProjectIDs {
                if let index = projects.firstIndex(where: { $0.id == id }) {
                    projects[index].isFavorite = setFavorite
                    updated.append(projects[index])
                }
            }
            return updated
        }
    }

    func updateProjectColorLabel(_ project: ProjectRecord, colorLabel: ColorLabel) async throws {
        var updated = project
        updated.colorLabel = colorLabel
        try await database.saveProject(updated)
        applyUpdatedProject(updated)
    }

    func batchSetColorLabel(_ colorLabel: ColorLabel) async throws {
        try await performBatchUpdate { projects in
            var updated: [ProjectRecord] = []
            for id in selectedProjectIDs {
                if let index = projects.firstIndex(where: { $0.id == id }) {
                    projects[index].colorLabel = colorLabel
                    updated.append(projects[index])
                }
            }
            return updated
        }
    }

    func colorLabelCount(for label: ColorLabel) -> Int {
        colorLabelCounts[label] ?? 0
    }

}
