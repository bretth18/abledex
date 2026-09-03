//
//  AppState+Projects.swift
//  abledex
//

import Foundation
import AppKit

extension AppState {
    // MARK: - Project Actions

    /// Opens a project in Live. With more than one Live installed, this either
    /// uses the remembered install or asks which one to use; `install`
    /// overrides both for a one-off open.
    func openProject(_ project: ProjectRecord, using install: AbletonInstall? = nil) {
        guard isProjectReachable(project) else { return }

        if let install {
            launch(project, with: install)
            return
        }

        Task {
            let installs = await AbletonInstallFinder.findInstalls()
            abletonInstalls = installs

            if installs.count <= 1 {
                // One install (or none — let LaunchServices decide, which may
                // still find Live somewhere abledex does not look).
                launch(project, with: installs.first)
            } else if let remembered = AbletonPreference.rememberedInstall(among: installs) {
                launch(project, with: remembered)
            } else {
                pendingOpen = PendingOpen(project: project, installs: installs)
            }
        }
    }

    /// Opens every selected project, asking at most once which Live to use.
    func openProjects(_ projectsToOpen: [ProjectRecord]) {
        guard !projectsToOpen.isEmpty else { return }
        guard projectsToOpen.count > 1 else {
            openProject(projectsToOpen[0])
            return
        }

        Task {
            let installs = await AbletonInstallFinder.findInstalls()
            abletonInstalls = installs

            let reachable = projectsToOpen.filter { FileManager.default.fileExists(atPath: $0.alsFilePath) }
            guard !reachable.isEmpty else {
                _ = isProjectReachable(projectsToOpen[0])
                return
            }

            if installs.count > 1, AbletonPreference.rememberedInstall(among: installs) == nil {
                pendingOpen = PendingOpen(project: reachable[0], installs: installs, additionalProjects: Array(reachable.dropFirst()))
                return
            }

            let install = AbletonPreference.rememberedInstall(among: installs) ?? installs.first
            for project in reachable {
                launch(project, with: install)
            }
        }
    }

    /// Resolves the sheet: opens the pending project (and any queued siblings)
    /// with `install`, optionally making it the default for future opens.
    func completePendingOpen(with install: AbletonInstall, remember: Bool) {
        guard let pending = pendingOpen else { return }
        pendingOpen = nil
        if remember {
            AbletonPreference.remember(install)
        }
        launch(pending.project, with: install)
        for project in pending.additionalProjects {
            launch(project, with: install)
        }
    }

    func cancelPendingOpen() {
        pendingOpen = nil
    }

    /// Reports the reachability of a project's .als, surfacing an alert when it
    /// cannot be opened. Judged by the file itself rather than the offline flag:
    /// volumes mounted outside /Volumes (network shares, secondary APFS volumes)
    /// are reachable even with no /Volumes/<name> mount point.
    private func isProjectReachable(_ project: ProjectRecord) -> Bool {
        if FileManager.default.fileExists(atPath: project.alsFilePath) { return true }
        let message = isVolumeOnline(project)
            ? "\"\(project.name)\" could not be found at \(project.alsFilePath). It may have been moved or deleted. Try re-scanning."
            : "\"\(project.name)\" is on \"\(project.sourceVolume)\", which isn't currently mounted. Connect the drive and try again."
        activeError = UserFacingError(title: "Project Not Available", message: message)
        return false
    }

    /// Launches `project`, in `install` when one is given and via LaunchServices
    /// otherwise, then stamps the open time.
    private func launch(_ project: ProjectRecord, with install: AbletonInstall?) {
        let alsURL = URL(fileURLWithPath: project.alsFilePath)
        let projectID = project.id
        let configuration = NSWorkspace.OpenConfiguration()

        Task {
            do {
                // Async variants; the sync open() blocks the main actor while Live launches.
                if let install {
                    try await NSWorkspace.shared.open([alsURL], withApplicationAt: install.url, configuration: configuration)
                } else {
                    try await NSWorkspace.shared.open(alsURL, configuration: configuration)
                }
            } catch {
                reportError("Failed to Open Project", error)
                return
            }

            // Stamp the CURRENT record: Live can take many seconds to launch, and
            // saving the click-time snapshot would revert edits made meanwhile.
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
