//
//  AppTheme+System.swift
//  abledex
//
//  Created by Brett Henderson on 1/30/26.
//

import SwiftUI
import AppKit

extension AppTheme {
    static let system = AppTheme(
        // Surfaces
        background: Color(nsColor: .windowBackgroundColor),
        surfacePrimary: Color(nsColor: .quaternaryLabelColor),
        surfaceSecondary: Color(nsColor: .quaternaryLabelColor),
        surfaceSelected: Color.accentColor.opacity(0.2),
        barBackground: Color(nsColor: .windowBackgroundColor),
        usesCustomBackground: false,
        showsBorder: false,

        // Borders
        border: Color.clear,
        separator: Color(nsColor: .separatorColor),

        // Text
        textPrimary: Color.primary,
        textSecondary: Color.secondary,
        textTertiary: Color(nsColor: .tertiaryLabelColor),

        // Accent
        accent: Color.accentColor,
        accentSubtle: Color.accentColor.opacity(0.1),

        // Status
        statusNone: Color.secondary,
        statusIdea: Color.yellow,
        statusInProgress: Color.blue,
        statusMixing: Color.purple,
        statusDone: Color.green,

        // Components
        badgeBackground: Color.accentColor.opacity(0.1),
        badgeForeground: Color.accentColor,
        cardBackground: Color(nsColor: .quaternaryLabelColor),

        // Waveform
        waveformPlayed: Color.accentColor,
        waveformUnplayed: Color.gray.opacity(0.3),
        waveformPlayhead: Color.accentColor,

        // Scrubber
        scrubberTrack: Color.gray.opacity(0.3),
        scrubberFill: Color.accentColor,

        // Charts
        chartPrimary: Color.blue,
        chartSecondary: Color.green,

        // XML Viewer
        xmlBackground: NSColor.textBackgroundColor,
        xmlForeground: NSColor.textColor,

        // Color labels, matching current behavior
        colorLabelColors: [
            .none: .clear,
            .red: .red,
            .orange: .orange,
            .yellow: .yellow,
            .green: .green,
            .blue: .blue,
            .purple: .purple,
            .gray: .gray,
        ],

        windowBackground: nil,

        preferredColorScheme: nil
    )
}
