//
//  ExportService.swift
//  abledex
//

import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum ExportService {
    /// Prompts for a destination and writes the given projects as CSV.
    /// Exports whatever the caller passes — typically the current filtered view.
    static func exportCSV(projects: [ProjectRecord]) throws {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "abledex-library.csv"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        try makeCSV(projects: projects).write(to: url, atomically: true, encoding: .utf8)
    }

    static func makeCSV(projects: [ProjectRecord]) -> String {
        let header = [
            "Name", "Folder", "Volume", "BPM", "Keys", "Tracks", "Duration (s)",
            "Ableton Version", "Status", "Favorite", "Tags", "Plugins",
            "Created", "Modified", "Last Opened", "Notes"
        ]

        let dateFormatter = ISO8601DateFormatter()

        var lines = [header.map(escape).joined(separator: ",")]
        for project in projects {
            // Built with appends — a single mixed-expression array literal here
            // exceeds the CI toolchain's type-check time limit.
            let bpm: String = project.bpm.map { String(format: "%.2f", $0) } ?? ""
            let duration: String = project.duration.map { String(format: "%.1f", $0) } ?? ""
            let created: String = project.createdDate.map(dateFormatter.string) ?? ""
            let modified: String = dateFormatter.string(from: project.modifiedDate ?? project.filesystemModifiedDate)
            let lastOpened: String = project.lastOpenedAt.map(dateFormatter.string) ?? ""

            var fields: [String] = []
            fields.append(project.name)
            fields.append(project.folderPath)
            fields.append(project.sourceVolume)
            fields.append(bpm)
            fields.append(project.musicalKeys.joined(separator: "; "))
            fields.append(String(project.totalTrackCount))
            fields.append(duration)
            fields.append(project.abletonVersion ?? "")
            fields.append(project.completionStatus.label)
            fields.append(project.isFavorite ? "Yes" : "No")
            fields.append(project.userTags.joined(separator: "; "))
            fields.append(project.plugins.joined(separator: "; "))
            fields.append(created)
            fields.append(modified)
            fields.append(lastOpened)
            fields.append(project.userNotes ?? "")
            lines.append(fields.map(escape).joined(separator: ","))
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
