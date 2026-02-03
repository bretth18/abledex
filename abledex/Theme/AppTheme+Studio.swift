//
//  AppTheme+Studio.swift
//  abledex
//
//  Created by Brett Henderson on 1/30/26.
//

import SwiftUI
import AppKit

extension AppTheme {
    static let studio: AppTheme = {
        let abletonOrange = Color(red: 0.95, green: 0.55, blue: 0.0)

        return AppTheme(
            // Surfaces
            background: Color(white: 0.08),
            surfacePrimary: Color(white: 0.12),
            surfaceSecondary: Color(white: 0.15),
            surfaceSelected: abletonOrange.opacity(0.2),
            barBackground: Color(white: 0.10),
            usesCustomBackground: true,
            showsBorder: true,

            // Borders
            border: Color(white: 0.35),
            separator: Color(white: 0.25),

            // Text
            textPrimary: Color(white: 0.92),
            textSecondary: Color(white: 0.55),
            textTertiary: Color(white: 0.35),

            // Accent
            accent: abletonOrange,
            accentSubtle: abletonOrange.opacity(0.1),

            // Status — brighter for contrast on dark
            statusNone: Color(white: 0.55),
            statusIdea: Color(red: 1.0, green: 0.85, blue: 0.2),
            statusInProgress: Color(red: 0.3, green: 0.6, blue: 1.0),
            statusMixing: Color(red: 0.7, green: 0.4, blue: 1.0),
            statusDone: Color(red: 0.3, green: 0.9, blue: 0.4),

            // Components
            badgeBackground: abletonOrange.opacity(0.15),
            badgeForeground: abletonOrange,
            cardBackground: Color(white: 0.12),

            // Waveform
            waveformPlayed: abletonOrange,
            waveformUnplayed: Color(white: 0.2),
            waveformPlayhead: Color.white,

            // Scrubber
            scrubberTrack: Color(white: 0.2),
            scrubberFill: abletonOrange,

            // Charts
            chartPrimary: abletonOrange,
            chartSecondary: Color(red: 0.3, green: 0.9, blue: 0.4),

            // XML Viewer
            xmlBackground: NSColor(white: 0.08, alpha: 1.0),
            xmlForeground: NSColor(white: 0.85, alpha: 1.0),

            // Color labels — boosted saturation+brightness for dark background
            colorLabelColors: [
                .none: .clear,
                .red: Color(red: 1.0, green: 0.35, blue: 0.35),
                .orange: Color(red: 1.0, green: 0.6, blue: 0.2),
                .yellow: Color(red: 1.0, green: 0.9, blue: 0.3),
                .green: Color(red: 0.3, green: 0.9, blue: 0.4),
                .blue: Color(red: 0.35, green: 0.65, blue: 1.0),
                .purple: Color(red: 0.7, green: 0.45, blue: 1.0),
                .gray: Color(white: 0.55),
            ],

            windowBackground: NSColor(white: 0.08, alpha: 1.0),

            preferredColorScheme: .dark
        )
    }()
}
