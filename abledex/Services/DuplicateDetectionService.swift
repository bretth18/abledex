//
//  DuplicateDetectionService.swift
//  abledex
//
//  Created by Brett Henderson on 12/23/25.
//

import Foundation

enum DuplicateType: String, Sendable {
    case exact = "Exact"       // Same file hash
    case similar = "Similar"   // Similar BPM and overlapping plugins
    case family = "Family"     // Same project folder
}

struct DuplicateGroup: Identifiable, Sendable {
    let id = UUID()
    let type: DuplicateType
    let projects: [ProjectRecord]

    var primaryProject: ProjectRecord? {
        // Most recently modified project is considered the "primary"
        projects.max { ($0.modifiedDate ?? $0.filesystemModifiedDate) < ($1.modifiedDate ?? $1.filesystemModifiedDate) }
    }
}

struct DuplicateDetectionService: Sendable {

    /// Find all duplicate groups in the given projects
    func findDuplicates(in projects: [ProjectRecord]) -> [DuplicateGroup] {
        var groups: [DuplicateGroup] = []

        // Find exact duplicates (same hash)
        groups.append(contentsOf: findExactDuplicates(in: projects))

        // Find similar projects (same BPM range, overlapping plugins)
        groups.append(contentsOf: findSimilarProjects(in: projects))

        return groups
    }

    /// Find projects with identical file hashes
    private func findExactDuplicates(in projects: [ProjectRecord]) -> [DuplicateGroup] {
        // Group by hash
        var hashGroups: [String: [ProjectRecord]] = [:]

        for project in projects {
            guard let hash = project.fileHash else { continue }
            hashGroups[hash, default: []].append(project)
        }

        // Return groups with more than one project
        return hashGroups.values
            .filter { $0.count > 1 }
            .map { DuplicateGroup(type: .exact, projects: $0) }
    }

    /// Find projects with similar characteristics
    private func findSimilarProjects(in projects: [ProjectRecord]) -> [DuplicateGroup] {
        var groups: [DuplicateGroup] = []
        var processed = Set<UUID>()

        for project in projects {
            guard !processed.contains(project.id) else { continue }
            guard project.bpm != nil else { continue }

            var similar: [ProjectRecord] = [project]

            for other in projects {
                guard other.id != project.id else { continue }
                guard !processed.contains(other.id) else { continue }

                if isSimilar(project, other) {
                    similar.append(other)
                    processed.insert(other.id)
                }
            }

            if similar.count > 1 {
                groups.append(DuplicateGroup(type: .similar, projects: similar))
                processed.insert(project.id)
            }
        }

        return groups
    }

    /// Check if two projects are similar (BPM within 5, >50% plugin overlap)
    private func isSimilar(_ a: ProjectRecord, _ b: ProjectRecord) -> Bool {
        // Same hash means exact duplicate, handled separately
        if a.fileHash != nil && a.fileHash == b.fileHash {
            return false
        }

        // Check BPM similarity (within 5 BPM)
        guard let bpmA = a.bpm, let bpmB = b.bpm else { return false }
        let bpmDiff = abs(bpmA - bpmB)
        guard bpmDiff <= 5 else { return false }

        // Check plugin overlap (>50%)
        let pluginsA = Set(a.plugins)
        let pluginsB = Set(b.plugins)

        guard !pluginsA.isEmpty && !pluginsB.isEmpty else { return false }

        let overlap = pluginsA.intersection(pluginsB).count
        let minCount = min(pluginsA.count, pluginsB.count)
        let overlapRatio = Double(overlap) / Double(minCount)

        return overlapRatio > 0.5
    }

    /// Get duplicate projects for a specific project
    func duplicatesOf(_ project: ProjectRecord, in allProjects: [ProjectRecord]) -> [ProjectRecord] {
        var duplicates: [ProjectRecord] = []

        // Exact duplicates (same hash)
        if let hash = project.fileHash {
            duplicates.append(contentsOf: allProjects.filter {
                $0.id != project.id && $0.fileHash == hash
            })
        }

        // Similar projects
        duplicates.append(contentsOf: allProjects.filter {
            $0.id != project.id && isSimilar(project, $0)
        })

        return duplicates
    }

    /// Check if a project has any duplicates
    func hasDuplicates(_ project: ProjectRecord, in allProjects: [ProjectRecord]) -> Bool {
        !duplicatesOf(project, in: allProjects).isEmpty
    }
}
