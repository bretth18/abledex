//
//  SidebarSection.swift
//  abledex
//
//  Created by Brett Henderson on 12/23/25.
//

import Foundation

enum SidebarSection: String, CaseIterable, Codable, Identifiable {
    case status = "Status"
    case colors = "Colors"
    case plugins = "Plugins"
    case keys = "Keys"
    case folders = "Project Folders"
    case tags = "Tags"
    case volumes = "Volumes"
    case locations = "Locations"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .status: return "checkmark.circle"
        case .colors: return "circle.fill"
        case .plugins: return "puzzlepiece.extension"
        case .keys: return "music.note"
        case .folders: return "folder"
        case .tags: return "tag"
        case .volumes: return "externaldrive"
        case .locations: return "folder.badge.plus"
        }
    }

    static let defaultOrder: [SidebarSection] = [
        .status, .colors, .plugins, .keys, .folders, .tags, .volumes, .locations
    ]
}

// MARK: - Sidebar Order Storage

enum SidebarOrderStorage {
    private static let key = "sidebarSectionOrder"

    static var order: [SidebarSection] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([SidebarSection].self, from: data) else {
                return SidebarSection.defaultOrder
            }
            // Ensure all sections are present (in case new ones were added)
            var result = decoded.filter { SidebarSection.allCases.contains($0) }
            for section in SidebarSection.allCases where !result.contains(section) {
                result.append(section)
            }
            return result
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
