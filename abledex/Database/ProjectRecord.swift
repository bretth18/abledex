//
//  ProjectRecord.swift
//  abledex
//
//  Created by Brett Henderson on 12/14/25.
//

import Foundation
import GRDB

enum CompletionStatus: Int, Codable, Sendable, CaseIterable {
    case none = 0
    case idea = 1
    case inProgress = 2
    case mixing = 3
    case done = 4

    var label: String {
        switch self {
        case .none: return "Not Set"
        case .idea: return "Idea"
        case .inProgress: return "In Progress"
        case .mixing: return "Mixing"
        case .done: return "Done"
        }
    }

    var icon: String {
        switch self {
        case .none: return "circle.dashed"
        case .idea: return "lightbulb"
        case .inProgress: return "hammer"
        case .mixing: return "slider.horizontal.3"
        case .done: return "checkmark.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .none: return "secondary"
        case .idea: return "yellow"
        case .inProgress: return "blue"
        case .mixing: return "purple"
        case .done: return "green"
        }
    }
}

struct ProjectRecord: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "projects"

    var id: UUID
    var name: String
    var folderPath: String
    var alsFilePath: String
    var sourceVolume: String

    // Dates from the .als XML (the "true" dates)
    var createdDate: Date?
    var modifiedDate: Date?

    // Filesystem date (may differ if file was copied)
    var filesystemModifiedDate: Date

    // Musical properties
    var bpm: Double?
    var timeSignatureNumerator: Int?
    var timeSignatureDenominator: Int?

    // Track counts
    var audioTrackCount: Int
    var midiTrackCount: Int
    var returnTrackCount: Int
    var totalTrackCount: Int

    // Ableton info
    var abletonVersion: String?
    var abletonMinorVersion: String?

    // Duration in seconds (arrangement length)
    var duration: Double?

    // JSON-encoded arrays
    var samplePathsJSON: String?
    var pluginsJSON: String?
    var musicalKeysJSON: String?

    // Computed metadata
    var hasMissingSamples: Bool
    var fileHash: String?

    // Indexing
    var lastIndexedAt: Date

    // User-added metadata (stored locally, not in .als)
    var userTagsJSON: String?
    var userNotes: String?
    var completionStatus: CompletionStatus
    var isFavorite: Bool
    var lastOpenedAt: Date?

    enum Columns: String, ColumnExpression {
        case id
        case name
        case folderPath
        case alsFilePath
        case sourceVolume
        case createdDate
        case modifiedDate
        case filesystemModifiedDate
        case bpm
        case timeSignatureNumerator
        case timeSignatureDenominator
        case audioTrackCount
        case midiTrackCount
        case returnTrackCount
        case totalTrackCount
        case abletonVersion
        case abletonMinorVersion
        case duration
        case samplePathsJSON
        case pluginsJSON
        case musicalKeysJSON
        case hasMissingSamples
        case fileHash
        case lastIndexedAt
        case userTagsJSON
        case userNotes
        case completionStatus
        case isFavorite
        case lastOpenedAt
    }
}

// MARK: - Convenience accessors for JSON fields

extension ProjectRecord {
    var samplePaths: [String] {
        get {
            guard let json = samplePathsJSON,
                  let data = json.data(using: .utf8),
                  let paths = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return paths
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                samplePathsJSON = json
            }
        }
    }

    var plugins: [String] {
        get {
            guard let json = pluginsJSON,
                  let data = json.data(using: .utf8),
                  let plugins = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return plugins
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                pluginsJSON = json
            }
        }
    }

    var userTags: [String] {
        get {
            guard let json = userTagsJSON,
                  let data = json.data(using: .utf8),
                  let tags = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return tags
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                userTagsJSON = json
            }
        }
    }

    var musicalKeys: [String] {
        get {
            guard let json = musicalKeysJSON,
                  let data = json.data(using: .utf8),
                  let keys = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return keys
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                musicalKeysJSON = json
            }
        }
    }

    var timeSignature: String? {
        guard let num = timeSignatureNumerator, let denom = timeSignatureDenominator else {
            return nil
        }
        return "\(num)/\(denom)"
    }

    var projectFolderName: String {
        URL(fileURLWithPath: folderPath).lastPathComponent
    }

    var formattedDuration: String? {
        guard let duration = duration else { return nil }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Returns keys in Camelot notation (e.g., "8A" for A Minor)
    var musicalKeysCamelot: [String] {
        musicalKeys.compactMap { CamelotConverter.toCamelot($0) }
    }
}

// MARK: - Camelot Notation Converter

enum CamelotConverter {
    // Camelot wheel mapping: key name -> Camelot code
    private static let camelotMap: [String: String] = [
        // Major keys (B column)
        "C Major": "8B",
        "C# Major": "3B",
        "D Major": "10B",
        "D# Major": "5B",
        "E Major": "12B",
        "F Major": "7B",
        "F# Major": "2B",
        "G Major": "9B",
        "G# Major": "4B",
        "A Major": "11B",
        "A# Major": "6B",
        "B Major": "1B",

        // Minor keys (A column)
        "C Minor": "5A",
        "C# Minor": "12A",
        "D Minor": "7A",
        "D# Minor": "2A",
        "E Minor": "9A",
        "F Minor": "4A",
        "F# Minor": "11A",
        "G Minor": "6A",
        "G# Minor": "1A",
        "A Minor": "8A",
        "A# Minor": "3A",
        "B Minor": "10A",

        // Common modes mapped to their relative position
        "C Dorian": "6A",
        "D Dorian": "8A",
        "E Dorian": "10A",
        "F Dorian": "11A",
        "G Dorian": "1A",
        "A Dorian": "3A",
        "B Dorian": "5A",

        "C Mixolydian": "7B",
        "D Mixolydian": "9B",
        "E Mixolydian": "11B",
        "F Mixolydian": "12B",
        "G Mixolydian": "2B",
        "A Mixolydian": "4B",
        "B Mixolydian": "6B",
    ]

    static func toCamelot(_ key: String) -> String? {
        // Direct lookup first
        if let camelot = camelotMap[key] {
            return camelot
        }

        // Try to parse and find closest match for modes not in map
        // Return nil for exotic scales that don't map well to Camelot
        return nil
    }

    static func fromCamelot(_ code: String) -> String? {
        camelotMap.first { $0.value == code }?.key
    }
}
