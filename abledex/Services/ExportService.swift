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
            let fields = [
                project.name,
                project.folderPath,
                project.sourceVolume,
                project.bpm.map { String(format: "%.2f", $0) } ?? "",
                project.musicalKeys.joined(separator: "; "),
                String(project.totalTrackCount),
                project.duration.map { String(format: "%.1f", $0) } ?? "",
                project.abletonVersion ?? "",
                project.completionStatus.label,
                project.isFavorite ? "Yes" : "No",
                project.userTags.joined(separator: "; "),
                project.plugins.joined(separator: "; "),
                project.createdDate.map(dateFormatter.string) ?? "",
                dateFormatter.string(from: project.modifiedDate ?? project.filesystemModifiedDate),
                project.lastOpenedAt.map(dateFormatter.string) ?? "",
                project.userNotes ?? ""
            ]
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
