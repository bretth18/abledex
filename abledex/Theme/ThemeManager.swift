//
//  ThemeManager.swift
//  abledex
//
//  Created by Brett Henderson on 1/30/26.
//

import SwiftUI

@MainActor @Observable
final class ThemeManager {
    var selectedThemeName: ThemeName {
        didSet {
            UserDefaults.standard.set(selectedThemeName.rawValue, forKey: "selectedTheme")
        }
    }

    var current: AppTheme {
        switch selectedThemeName {
        case .system: return .system
        case .studio: return .studio
        }
    }

    init() {
        if let stored = UserDefaults.standard.string(forKey: "selectedTheme"),
           let name = ThemeName(rawValue: stored) {
            self.selectedThemeName = name
        } else {
            self.selectedThemeName = .system
        }
    }
}
