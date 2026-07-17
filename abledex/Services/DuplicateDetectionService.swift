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

    /// Find projects with similar characteristics. Similarity requires BPM
    /// within ±5, so candidates bucket by integer BPM and compare only against
    /// neighboring buckets — near-linear instead of all-pairs O(n²).
    private func findSimilarProjects(in projects: [ProjectRecord]) -> [DuplicateGroup] {
        // Pre-decode all plugin sets once to avoid repeated JSON decoding + lock contention
        var pluginSetsById: [UUID: Set<String>] = [:]
        pluginSetsById.reserveCapacity(projects.count)
        for project in projects {
            let plugins = project.plugins
            if !plugins.isEmpty {
                pluginSetsById[project.id] = Set(plugins)
            }
        }

        // Similarity needs a BPM and plugins
        let candidates = projects.filter { $0.bpm != nil && pluginSetsById[$0.id] != nil }

        var buckets: [Int: [Int]] = [:]  // integer bpm -> indexes into candidates
        for (index, project) in candidates.enumerated() {
            buckets[Int(project.bpm!), default: []].append(index)
        }

        var groups: [DuplicateGroup] = []
        var processed = Set<UUID>()

        for (index, project) in candidates.enumerated() {
            guard !processed.contains(project.id) else { continue }

            var similar: [ProjectRecord] = [project]
            let bucket = Int(project.bpm!)

            for neighborBucket in (bucket - 5)...(bucket + 5) {
                for otherIndex in buckets[neighborBucket] ?? [] {
                    let other = candidates[otherIndex]
                    guard otherIndex != index, !processed.contains(other.id) else { continue }

                    if isSimilarFast(project, other, pluginsA: pluginSetsById[project.id], pluginsB: pluginSetsById[other.id]) {
                        similar.append(other)
                        processed.insert(other.id)
                    }
                }
            }

            if similar.count > 1 {
                groups.append(DuplicateGroup(type: .similar, projects: similar))
                processed.insert(project.id)
            }
        }

        return groups
    }

    /// Fast similarity check using pre-decoded plugin sets
    private func isSimilarFast(_ a: ProjectRecord, _ b: ProjectRecord, pluginsA: Set<String>?, pluginsB: Set<String>?) -> Bool {
        // Same hash means exact duplicate, handled separately
        if a.fileHash != nil && a.fileHash == b.fileHash {
            return false
        }

        // Check BPM similarity (within 5 BPM)
        guard let bpmA = a.bpm, let bpmB = b.bpm else { return false }
        guard abs(bpmA - bpmB) <= 5 else { return false }

        // Check plugin overlap (>50%) using pre-decoded sets
        guard let pluginsA = pluginsA, let pluginsB = pluginsB,
              !pluginsA.isEmpty, !pluginsB.isEmpty else { return false }

        let overlap = pluginsA.intersection(pluginsB).count
        let minCount = min(pluginsA.count, pluginsB.count)

        return Double(overlap) / Double(minCount) > 0.5
    }
}
