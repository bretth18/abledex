//
//  ProjectRecord.swift
//  abledex
//
//  Created by Brett Henderson on 12/14/25.
//

import Foundation
import GRDB
import SwiftUI

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

enum ColorLabel: Int, Codable, Sendable, CaseIterable {
    case none = 0
    case red = 1
    case orange = 2
    case yellow = 3
    case green = 4
    case blue = 5
    case purple = 6
    case gray = 7

    var label: String {
        switch self {
        case .none: return "None"
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .gray: return "Gray"
        }
    }

    var systemColor: String {
        switch self {
        case .none: return "clear"
        case .red: return "red"
        case .orange: return "orange"
        case .yellow: return "yellow"
        case .green: return "green"
        case .blue: return "blue"
        case .purple: return "purple"
        case .gray: return "gray"
        }
    }
    
    var color: Color {
        switch self {
        case .none: return .primary
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .gray: return .gray
        }
    }
}

struct ProjectRecord: Codable, Sendable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
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
    // .als size in bytes at last index; part of change detection (nil = legacy row)
    var fileSize: Int64? = nil

    // Indexing
    var lastIndexedAt: Date

    // User-added metadata (stored locally, not in .als)
    var userTagsJSON: String?
    var userNotes: String?
    var completionStatus: CompletionStatus
    var colorLabel: ColorLabel
    var isFavorite: Bool
    var lastOpenedAt: Date?

    // Music project (EP/album) this project belongs to, if any
    var collectionID: UUID? = nil
    // Track order within that music project; nil sorts last
    var collectionPosition: Int? = nil

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
        case fileSize
        case lastIndexedAt
        case userTagsJSON
        case userNotes
        case completionStatus
        case colorLabel
        case isFavorite
        case lastOpenedAt
        case collectionID
        case collectionPosition
    }
}

// MARK: - JSON Decoding Cache

/// Thread-safe LRU-ish cache for decoded JSON arrays to avoid repeated decoding.
/// Each entry carries a monotonically increasing generation stamp updated on access,
/// making cache hits O(1). Eviction happens only on insert when over capacity,
/// dropping the least-recently-used quarter of entries in one pass to amortize cost.
private final class JSONDecodeCache: @unchecked Sendable {
    static let shared = JSONDecodeCache()

    private static let maxEntries = 2000

    private var cache: [String: (value: [String], generation: UInt64)] = [:]
    private var generation: UInt64 = 0
    private let lock = NSLock()
    private let decoder = JSONDecoder()

    func decode(_ json: String?) -> [String] {
        guard let json = json else { return [] }

        lock.lock()

        // Check cache first
        if let cached = cache[json] {
            // Stamp with the latest generation (most recently used)
            generation += 1
            cache[json] = (cached.value, generation)
            lock.unlock()
            return cached.value
        }

        lock.unlock()

        // Decode outside lock to avoid holding it during JSON parsing
        guard let data = json.data(using: .utf8),
              let decoded = try? decoder.decode([String].self, from: data) else {
            return []
        }

        lock.lock()
        generation += 1
        cache[json] = (decoded, generation)

        // Evict the least-recently-used ~25% of entries if over capacity
        if cache.count > Self.maxEntries {
            let evictCount = Self.maxEntries / 4
            let cutoff = cache.values
                .map(\.generation)
                .sorted()[evictCount]
            for (key, entry) in cache where entry.generation < cutoff {
                cache.removeValue(forKey: key)
            }
        }

        lock.unlock()
        return decoded
    }

    /// Clear cache (e.g., after a full re-scan)
    func clear() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }
}

// MARK: - Convenience accessors for JSON fields

extension ProjectRecord {
    var samplePaths: [String] {
        get {
            JSONDecodeCache.shared.decode(samplePathsJSON)
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
            JSONDecodeCache.shared.decode(pluginsJSON)
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
            JSONDecodeCache.shared.decode(userTagsJSON)
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
            JSONDecodeCache.shared.decode(musicalKeysJSON)
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
        // Use string manipulation instead of URL for performance
        if let lastSlash = folderPath.lastIndex(of: "/") {
            return String(folderPath[folderPath.index(after: lastSlash)...])
        }
        return folderPath
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

nonisolated enum CamelotConverter {
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
