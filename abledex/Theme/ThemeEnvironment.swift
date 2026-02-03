//
//  ThemeEnvironment.swift
//  abledex
//
//  Created by Brett Henderson on 1/30/26.
//

import SwiftUI
import AppKit

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .system
}

extension EnvironmentValues {
    var theme: AppTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Window Background Modifier

/// Sets the NSWindow backgroundColor directly so the custom theme background
/// fills the entire window, including behind NavigationSplitView column chrome.
struct WindowBackgroundModifier: ViewModifier {
    let color: NSColor?

    func body(content: Content) -> some View {
        content
            .background(WindowBackgroundSetter(color: color))
    }
}

private struct WindowBackgroundSetter: NSViewRepresentable {
    let color: NSColor?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            if let color {
                window.backgroundColor = color
                setVibrancy(active: false, in: window.contentView)
            } else {
                window.backgroundColor = .windowBackgroundColor
                setVibrancy(active: true, in: window.contentView)
            }
        }
    }

    /// Recursively enable/disable NSVisualEffectViews that create the sidebar
    /// and content area translucency.
    private func setVibrancy(active: Bool, in view: NSView?) {
        guard let view else { return }
        if let effectView = view as? NSVisualEffectView {
            effectView.state = active ? .followsWindowActiveState : .inactive
            effectView.material = active ? .sidebar : .windowBackground
        }
        for subview in view.subviews {
            setVibrancy(active: active, in: subview)
        }
    }
}

extension View {
    func windowBackground(_ color: NSColor?) -> some View {
        modifier(WindowBackgroundModifier(color: color))
    }
}
