//
//  ThemedViewModifiers.swift
//  abledex
//
//  Created by Brett Henderson on 1/30/26.
//

import SwiftUI

// MARK: - Badge Style

enum BadgeStyle {
    case accent
    case neutral
    case tinted(Color)
}

struct ThemedBadgeModifier: ViewModifier {
    @Environment(\.theme) private var theme
    let style: BadgeStyle

    private var backgroundColor: Color {
        switch style {
        case .accent:
            return theme.badgeBackground
        case .neutral:
            return theme.surfacePrimary
        case .tinted(let color):
            return color.opacity(0.15)
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .accent:
            return theme.badgeForeground
        case .neutral:
            return theme.textSecondary
        case .tinted(let color):
            return color
        }
    }

    func body(content: Content) -> some View {
        content
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
            .overlay(
                theme.showsBorder
                    ? Capsule().stroke(theme.border, lineWidth: 0.5)
                    : nil
            )
    }
}

// MARK: - Card Style

struct ThemedCardModifier: ViewModifier {
    @Environment(\.theme) private var theme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                theme.showsBorder
                    ? RoundedRectangle(cornerRadius: cornerRadius).stroke(theme.border, lineWidth: 0.5)
                    : nil
            )
    }
}

// MARK: - View Extensions

extension View {
    func themedBadge(_ style: BadgeStyle = .accent) -> some View {
        modifier(ThemedBadgeModifier(style: style))
    }

    func themedCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(ThemedCardModifier(cornerRadius: cornerRadius))
    }
}
