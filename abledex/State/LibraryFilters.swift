//
//  LibraryFilters.swift
//  abledex
//

import Foundation

enum SortColumn: String, CaseIterable, Sendable {
    case name = "Name"
    case bpm = "BPM"
    case createdDate = "Created"
    case modifiedDate = "Modified"
    case tracks = "Tracks"
    case version = "Version"
    case duration = "Duration"
    case status = "Status"
    case lastOpened = "Last Opened"
}

enum ProjectFilter: String, CaseIterable, Sendable {
    case all = "All Projects"
    case favorites = "Favorites"
    case recentlyOpened = "Recently Opened"
    case recentlyModified = "Recently Modified"
    case missingSamples = "Missing Samples"
    case highBPM = "High BPM (130+)"
    case normalBPM = "Normal BPM (100-130)"
    case lowBPM = "Low BPM (<100)"
}

extension ProjectFilter {
    var icon: String {
        switch self {
        case .all: "music.note.list"
        case .favorites: "star.fill"
        case .recentlyOpened: "clock.arrow.circlepath"
        case .recentlyModified: "clock"
        case .missingSamples: "exclamationmark.triangle"
        case .highBPM: "hare"
        case .normalBPM: "figure.walk"
        case .lowBPM: "tortoise"
        }
    }
}
