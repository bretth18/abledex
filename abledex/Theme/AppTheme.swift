//
//  AppTheme.swift
//  abledex
//
//  Created by Brett Henderson on 1/30/26.
//

import SwiftUI
import AppKit

enum ThemeName: String, CaseIterable, Identifiable {
    case system = "System"
    case studio = "Studio"

    var id: String { rawValue }
}

struct AppTheme: Sendable {
    // MARK: - Surfaces
    let background: Color
    let surfacePrimary: Color
    let surfaceSecondary: Color
    let surfaceSelected: Color
    let barBackground: Color

    /// When true, views should hide the default system scroll/list/table backgrounds
    /// and apply theme.background instead.
    let usesCustomBackground: Bool

    /// When true, themed components draw visible borders
    let showsBorder: Bool

    // MARK: - Borders
    let border: Color
    let separator: Color

    // MARK: - Text
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color

    // MARK: - Accent
    let accent: Color
    let accentSubtle: Color

    // MARK: - Status
    let statusNone: Color
    let statusIdea: Color
    let statusInProgress: Color
    let statusMixing: Color
    let statusDone: Color

    // MARK: - Components
    let badgeBackground: Color
    let badgeForeground: Color
    let cardBackground: Color

    // MARK: - Waveform
    let waveformPlayed: Color
    let waveformUnplayed: Color
    let waveformPlayhead: Color

    // MARK: - Scrubber
    let scrubberTrack: Color
    let scrubberFill: Color

    // MARK: - Charts
    let chartPrimary: Color
    let chartSecondary: Color

    // MARK: - XML Viewer (NSColor for AppKit)
    let xmlBackground: NSColor
    let xmlForeground: NSColor

    // MARK: - Color Labels
    let colorLabelColors: [ColorLabel: Color]

    // MARK: - Window (NSColor for AppKit-level background)
    let windowBackground: NSColor?

    // MARK: - Preferred color scheme
    let preferredColorScheme: ColorScheme?

    // MARK: - Convenience

    func statusColor(for status: CompletionStatus) -> Color {
        switch status {
        case .none: return statusNone
        case .idea: return statusIdea
        case .inProgress: return statusInProgress
        case .mixing: return statusMixing
        case .done: return statusDone
        }
    }

    func colorLabel(for label: ColorLabel) -> Color {
        colorLabelColors[label] ?? .clear
    }
}
