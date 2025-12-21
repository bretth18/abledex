//
//  LocationRecord.swift
//  abledex
//
//  Created by Brett Henderson on 12/14/25.
//

import Foundation
import GRDB

struct LocationRecord: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "locations"

    var id: UUID
    var path: String
    var displayName: String
    var isAutoDetected: Bool
    var isEnabled: Bool
    var lastScannedAt: Date?
    var projectCount: Int

    enum Columns: String, ColumnExpression {
        case id
        case path
        case displayName
        case isAutoDetected
        case isEnabled
        case lastScannedAt
        case projectCount
    }
}

// MARK: - Factory methods

extension LocationRecord {
    static func autoDetected(path: String, displayName: String) -> LocationRecord {
        LocationRecord(
            id: UUID(),
            path: path,
            displayName: displayName,
            isAutoDetected: true,
            isEnabled: true,
            lastScannedAt: nil,
            projectCount: 0
        )
    }

    static func userAdded(path: String, displayName: String) -> LocationRecord {
        LocationRecord(
            id: UUID(),
            path: path,
            displayName: displayName,
            isAutoDetected: false,
            isEnabled: true,
            lastScannedAt: nil,
            projectCount: 0
        )
    }
}
