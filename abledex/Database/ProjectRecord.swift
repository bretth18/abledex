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

    // Computed metadata
    var hasMissingSamples: Bool

    // Indexing
    var lastIndexedAt: Date

    // User-added metadata (stored locally, not in .als)
    var userTagsJSON: String?
    var userNotes: String?
    var completionStatus: CompletionStatus

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
        case hasMissingSamples
        case lastIndexedAt
        case userTagsJSON
        case userNotes
        case completionStatus
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

    var timeSignature: String? {
        guard let num = timeSignatureNumerator, let denom = timeSignatureDenominator else {
            return nil
        }
        return "\(num)/\(denom)"
    }

    var formattedDuration: String? {
        guard let duration = duration else { return nil }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
