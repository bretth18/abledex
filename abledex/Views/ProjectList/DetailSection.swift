//
//  DetailSection.swift
//  abledex
//
//  Created by Brett Henderson on 12/23/25.
//

import Foundation

enum DetailSection: String, CaseIterable, Codable, Identifiable {
    case status = "Status"
    case color = "Color"
    case actions = "Actions"
    case tags = "Tags"
    case details = "Details"
    case plugins = "Plugins"
    case keys = "Keys"
    case audioPreview = "Audio Preview"
    case samples = "Samples"
    case versionTimeline = "Version Timeline"
    case notes = "Notes"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .status: return "checkmark.circle"
        case .color: return "circle.fill"
        case .actions: return "play.fill"
        case .tags: return "tag"
        case .details: return "info.circle"
        case .plugins: return "puzzlepiece.extension"
        case .keys: return "music.note"
        case .audioPreview: return "waveform"
        case .samples: return "folder"
        case .versionTimeline: return "clock.arrow.circlepath"
        case .notes: return "note.text"
        }
    }

    static let defaultOrder: [DetailSection] = [
        .status, .color, .actions, .tags, .details,
        .plugins, .keys, .audioPreview, .samples, .versionTimeline, .notes
    ]
}

// MARK: - Detail Order Storage

enum DetailOrderStorage {
    private static let key = "detailSectionOrder"

    static var order: [DetailSection] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([DetailSection].self, from: data) else {
                return DetailSection.defaultOrder
            }
            // Ensure all sections are present (in case new ones were added)
            var result = decoded.filter { DetailSection.allCases.contains($0) }
            for section in DetailSection.allCases where !result.contains(section) {
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
