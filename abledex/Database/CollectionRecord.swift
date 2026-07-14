//
//  CollectionRecord.swift
//  abledex
//

import Foundation
import GRDB

/// The release format of a music project (an overarching body of work
/// that groups individual Ableton projects).
enum CollectionKind: Int, Codable, Sendable, CaseIterable {
    case other = 0
    case single = 1
    case ep = 2
    case album = 3
    case compilation = 4

    var label: String {
        switch self {
        case .other: return "Project"
        case .single: return "Single"
        case .ep: return "EP"
        case .album: return "Album"
        case .compilation: return "Compilation"
        }
    }

    var icon: String {
        switch self {
        case .other: return "square.stack"
        case .single: return "smallcircle.circle"
        case .ep: return "circle.circle"
        case .album: return "opticaldisc"
        case .compilation: return "square.stack.3d.up"
        }
    }
}

enum CollectionStatus: Int, Codable, Sendable, CaseIterable {
    case planning = 0
    case inProgress = 1
    case mixing = 2
    case mastering = 3
    case released = 4

    var label: String {
        switch self {
        case .planning: return "Planning"
        case .inProgress: return "In Progress"
        case .mixing: return "Mixing"
        case .mastering: return "Mastering"
        case .released: return "Released"
        }
    }

    var icon: String {
        switch self {
        case .planning: return "lightbulb"
        case .inProgress: return "hammer"
        case .mixing: return "slider.horizontal.3"
        case .mastering: return "waveform.badge.magnifyingglass"
        case .released: return "checkmark.seal.fill"
        }
    }
}

/// A music project (EP, album, single...) that groups Ableton projects.
struct CollectionRecord: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "collections"

    var id: UUID
    var name: String
    var kind: CollectionKind
    var status: CollectionStatus
    var notes: String?
    var createdAt: Date

    enum Columns: String, ColumnExpression {
        case id
        case name
        case kind
        case status
        case notes
        case createdAt
    }

    static func new(name: String, kind: CollectionKind) -> CollectionRecord {
        CollectionRecord(id: UUID(), name: name, kind: kind, status: .planning, notes: nil, createdAt: Date())
    }
}
