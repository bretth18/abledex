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

/// Applies the theme's window background at the AppKit level.
///
/// Layout safety: `updateNSView` can fire inside `NSHostingView.layout()`, so it
/// must never mutate the window or its view hierarchy synchronously. Doing so
/// triggers "It's not legal to call -layoutSubtreeIfNeeded on a view which is
/// already being laid out". All mutation is therefore:
///   1. Deferred to the next runloop turn (coalesced to one pending apply).
///   2. Idempotent: every setter is guarded by a value check, and a whole apply
///      is skipped when the last-applied theme color and window are unchanged,
///      so repeated SwiftUI update passes never dirty AppKit layout.
private struct WindowBackgroundSetter: NSViewRepresentable {
    let color: NSColor?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WindowObservingView {
        let view = WindowObservingView()
        view.wantsLayer = true
        // Re-apply when the view (re)attaches to a window, since the window is
        // usually nil during the first update pass. The callback only schedules
        // deferred work, so it is safe even if fired mid-layout.
        view.onDidMoveToWindow = { [coordinator = context.coordinator] in
            coordinator.hostWindowChanged()
        }
        return view
    }

    func updateNSView(_ nsView: WindowObservingView, context: Context) {
        // No synchronous window/view mutation here: record the desired color
        // and schedule a deferred, coalesced apply.
        context.coordinator.setDesiredColor(color, host: nsView)
    }

    /// Plain NSView that reports window attachment changes.
    final class WindowObservingView: NSView {
        var onDidMoveToWindow: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onDidMoveToWindow?()
        }
    }

    @MainActor
    final class Coordinator {
        private weak var hostView: NSView?
        private var desiredColor: NSColor?
        private var applyPending = false

        // Last successfully applied state, so unchanged updates are no-ops.
        private var hasApplied = false
        private weak var appliedWindow: NSWindow?
        private var appliedColor: NSColor?

        func setDesiredColor(_ color: NSColor?, host: NSView) {
            hostView = host
            desiredColor = color
            scheduleApply()
        }

        func hostWindowChanged() {
            scheduleApply()
        }

        /// Defers the apply to the next runloop turn, coalescing repeated
        /// requests from the same (or consecutive) update passes.
        private func scheduleApply() {
            guard !applyPending else { return }
            applyPending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.applyPending = false
                    self.applyNow()
                }
            }
        }

        private func applyNow() {
            guard let window = hostView?.window else { return }

            // Skip entirely if this exact theme color is already applied to
            // this window, the common case on every SwiftUI update pass.
            if hasApplied, window === appliedWindow, appliedColor == desiredColor {
                return
            }

            let targetColor = desiredColor ?? .windowBackgroundColor
            if window.backgroundColor != targetColor {
                window.backgroundColor = targetColor
            }
            setVibrancy(active: desiredColor == nil, in: window.contentView)

            hasApplied = true
            appliedWindow = window
            appliedColor = desiredColor
        }

        /// Recursively enable/disable NSVisualEffectViews that create the sidebar
        /// and content area translucency. Each property is only written when its
        /// value actually differs, so re-walks never dirty layout.
        private func setVibrancy(active: Bool, in view: NSView?) {
            guard let view else { return }
            if let effectView = view as? NSVisualEffectView {
                let state: NSVisualEffectView.State = active ? .followsWindowActiveState : .inactive
                let material: NSVisualEffectView.Material = active ? .sidebar : .windowBackground
                if effectView.state != state {
                    effectView.state = state
                }
                if effectView.material != material {
                    effectView.material = material
                }
            }
            for subview in view.subviews {
                setVibrancy(active: active, in: subview)
            }
        }
    }
}

extension View {
    func windowBackground(_ color: NSColor?) -> some View {
        modifier(WindowBackgroundModifier(color: color))
    }
}
