//
//  AppDatabase.swift
//  abledex
//
//  Created by Brett Henderson on 12/14/25.
//

import Foundation
import GRDB

final class AppDatabase: Sendable {
    private let dbWriter: any DatabaseWriter

    private init(dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try Self.migrator.migrate(dbWriter)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1") { db in
            // Projects table
            try db.create(table: "projects") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("folderPath", .text).notNull()
                t.column("alsFilePath", .text).notNull().unique()
                t.column("sourceVolume", .text).notNull()

                t.column("createdDate", .datetime)
                t.column("modifiedDate", .datetime)
                t.column("filesystemModifiedDate", .datetime).notNull()

                t.column("bpm", .double)
                t.column("timeSignatureNumerator", .integer)
                t.column("timeSignatureDenominator", .integer)

                t.column("audioTrackCount", .integer).notNull().defaults(to: 0)
                t.column("midiTrackCount", .integer).notNull().defaults(to: 0)
                t.column("returnTrackCount", .integer).notNull().defaults(to: 0)
                t.column("totalTrackCount", .integer).notNull().defaults(to: 0)

                t.column("abletonVersion", .text)
                t.column("abletonMinorVersion", .text)

                t.column("duration", .double)

                t.column("samplePathsJSON", .text)
                t.column("pluginsJSON", .text)

                t.column("hasMissingSamples", .boolean).notNull().defaults(to: false)

                t.column("lastIndexedAt", .datetime).notNull()

                t.column("userTagsJSON", .text)
                t.column("userNotes", .text)
                t.column("completionStatus", .integer).notNull().defaults(to: 0)  // 0=none, 1=idea, 2=inProgress, 3=mixing, 4=done
                t.column("isFavorite", .boolean).notNull().defaults(to: false)
                t.column("lastOpenedAt", .datetime)
            }

            // Indexes for common queries
            try db.create(index: "projects_on_createdDate", on: "projects", columns: ["createdDate"])
            try db.create(index: "projects_on_modifiedDate", on: "projects", columns: ["modifiedDate"])
            try db.create(index: "projects_on_bpm", on: "projects", columns: ["bpm"])
            try db.create(index: "projects_on_sourceVolume", on: "projects", columns: ["sourceVolume"])
            try db.create(index: "projects_on_name", on: "projects", columns: ["name"])
            try db.create(index: "projects_on_folderPath", on: "projects", columns: ["folderPath"])

            // Locations table
            try db.create(table: "locations") { t in
                t.column("id", .text).primaryKey()
                t.column("path", .text).notNull().unique()
                t.column("displayName", .text).notNull()
                t.column("isAutoDetected", .boolean).notNull()
                t.column("isEnabled", .boolean).notNull().defaults(to: true)
                t.column("lastScannedAt", .datetime)
                t.column("projectCount", .integer).notNull().defaults(to: 0)
            }
        }

        migrator.registerMigration("v2") { db in
            // Add musical keys column for key/scale detection
            try db.alter(table: "projects") { t in
                t.add(column: "musicalKeysJSON", .text)
            }
        }

        migrator.registerMigration("v3") { db in
            // Add file hash column for duplicate detection
            try db.alter(table: "projects") { t in
                t.add(column: "fileHash", .text)
            }
            try db.create(index: "projects_on_fileHash", on: "projects", columns: ["fileHash"])
        }

        migrator.registerMigration("v4") { db in
            // Add color label column for project flagging
            try db.alter(table: "projects") { t in
                t.add(column: "colorLabel", .integer).notNull().defaults(to: 0)
            }
        }

        return migrator
    }
}

// MARK: - Database Access

extension AppDatabase {
    private static let dbFileName = "abledex.sqlite"

    static func live() throws -> AppDatabase {
        let fileManager = FileManager.default
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = appSupportURL.appendingPathComponent("Abledex", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let dbURL = directoryURL.appendingPathComponent(dbFileName)
        let dbPool = try DatabasePool(path: dbURL.path)

        return try AppDatabase(dbWriter: dbPool)
    }

    static func empty() throws -> AppDatabase {
        let dbQueue = try DatabaseQueue()
        return try AppDatabase(dbWriter: dbQueue)
    }
}

// MARK: - Project Operations

extension AppDatabase {
    func saveProject(_ project: ProjectRecord) async throws {
        try await dbWriter.write { db in
            try project.save(db, onConflict: .replace)
        }
    }

    func saveProjects(_ projects: [ProjectRecord]) async throws {
        try await dbWriter.write { db in
            for project in projects {
                // Use upsert to handle existing folderPath conflicts
                try project.upsert(db)
            }
        }
    }

    func deleteProject(id: UUID) async throws {
        _ = try await dbWriter.write { db in
            try db.execute(sql: "DELETE FROM projects WHERE id = ?", arguments: [id.uuidString])
        }
    }

    func deleteProjects(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        try await dbWriter.write { db in
            let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
            let sql = "DELETE FROM projects WHERE id IN (\(placeholders))"
            try db.execute(sql: sql, arguments: StatementArguments(ids.map { $0.uuidString }))
        }
    }

    func deleteProjectsAtPath(_ folderPath: String) async throws {
        try await dbWriter.write { db in
            _ = try ProjectRecord
                .filter(ProjectRecord.Columns.folderPath == folderPath)
                .deleteAll(db)
        }
    }

    func fetchAllProjects() async throws -> [ProjectRecord] {
        try await dbWriter.read { db in
            try ProjectRecord
                .order(ProjectRecord.Columns.modifiedDate.desc)
                .fetchAll(db)
        }
    }

    func fetchProjects(
        sortedBy column: ProjectRecord.Columns,
        ascending: Bool = true
    ) async throws -> [ProjectRecord] {
        try await dbWriter.read { db in
            let ordering = ascending ? column.asc : column.desc
            return try ProjectRecord.order(ordering).fetchAll(db)
        }
    }

    func fetchProjects(forVolume volume: String) async throws -> [ProjectRecord] {
        try await dbWriter.read { db in
            try ProjectRecord
                .filter(ProjectRecord.Columns.sourceVolume == volume)
                .order(ProjectRecord.Columns.modifiedDate.desc)
                .fetchAll(db)
        }
    }

    func fetchProjectsWithMissingSamples() async throws -> [ProjectRecord] {
        try await dbWriter.read { db in
            try ProjectRecord
                .filter(ProjectRecord.Columns.hasMissingSamples == true)
                .order(ProjectRecord.Columns.modifiedDate.desc)
                .fetchAll(db)
        }
    }

    func fetchProject(byFolderPath path: String) async throws -> ProjectRecord? {
        try await dbWriter.read { db in
            try ProjectRecord
                .filter(ProjectRecord.Columns.folderPath == path)
                .fetchOne(db)
        }
    }

    func searchProjects(query: String) async throws -> [ProjectRecord] {
        try await dbWriter.read { db in
            try ProjectRecord
                .filter(ProjectRecord.Columns.name.like("%\(query)%"))
                .order(ProjectRecord.Columns.name)
                .fetchAll(db)
        }
    }

    func fetchProjectCount() async throws -> Int {
        try await dbWriter.read { db in
            try ProjectRecord.fetchCount(db)
        }
    }

    func fetchUniqueVolumes() async throws -> [String] {
        try await dbWriter.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT DISTINCT sourceVolume FROM projects ORDER BY sourceVolume"
            )
        }
    }

    func fetchProjects(byAlsFilePaths paths: [String]) async throws -> [String: ProjectRecord] {
        guard !paths.isEmpty else { return [:] }
        return try await dbWriter.read { db in
            let records = try ProjectRecord
                .filter(paths.contains(ProjectRecord.Columns.alsFilePath))
                .fetchAll(db)
            return Dictionary(uniqueKeysWithValues: records.map { ($0.alsFilePath, $0) })
        }
    }
}

// MARK: - Location Operations

extension AppDatabase {
    func saveLocation(_ location: LocationRecord) async throws {
        try await dbWriter.write { db in
            try location.save(db)
        }
    }

    func deleteLocation(id: UUID) async throws {
        _ = try await dbWriter.write { db in
            try db.execute(sql: "DELETE FROM locations WHERE id = ?", arguments: [id.uuidString])
        }
    }

    func fetchAllLocations() async throws -> [LocationRecord] {
        try await dbWriter.read { db in
            try LocationRecord.order(LocationRecord.Columns.displayName).fetchAll(db)
        }
    }

    func fetchEnabledLocations() async throws -> [LocationRecord] {
        try await dbWriter.read { db in
            try LocationRecord
                .filter(LocationRecord.Columns.isEnabled == true)
                .order(LocationRecord.Columns.displayName)
                .fetchAll(db)
        }
    }

    func fetchLocation(byPath path: String) async throws -> LocationRecord? {
        try await dbWriter.read { db in
            try LocationRecord
                .filter(LocationRecord.Columns.path == path)
                .fetchOne(db)
        }
    }

    func updateLocationProjectCount(id: UUID, count: Int) async throws {
        try await dbWriter.write { db in
            try db.execute(
                sql: "UPDATE locations SET projectCount = ?, lastScannedAt = ? WHERE id = ?",
                arguments: [count, Date(), id.uuidString]
            )
        }
    }
}
