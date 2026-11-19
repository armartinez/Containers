//
//  NSApplication+ActivationPolicy.swift
//  Containers
//
//  Created by Axel Martinez on 2026/10/30.
//

import AppKit

extension NSApplication {
    /// Keeps a menu bar only app in the Dock, with its menus in the menu bar, while one of its windows is open.
    ///
    /// An accessory app has neither, so the dashboard and Settings would lose ⌘-Tab, the app's menus and their shortcuts.
    func beginUpdatingActivationPolicy() {
        let center = NotificationCenter.default

        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NSApp.updateActivationPolicy() }
        }

        center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { notification in
            // Still listed as open while it closes.
            let closing = (notification.object as? NSWindow).map(ObjectIdentifier.init)

            MainActor.assumeIsolated { NSApp.updateActivationPolicy(closing: closing) }
        }

        updateActivationPolicy()
    }

    /// Makes the app regular while one of its windows is open, and an accessory otherwise when its icon is in the menu bar.
    ///
    /// - Parameter closingWindow: A window that's closing, and still listed as open.
    func updateActivationPolicy(closing closingWindow: ObjectIdentifier? = nil) {
        let hasOpenWindow = windows.contains { window in
            ObjectIdentifier(window) != closingWindow && window.canBecomeMain && (window.isVisible || window.isMiniaturized)
        }
        let policy: ActivationPolicy = UserDefaults.appIconPlacement == .menuBar && !hasOpenWindow ? .accessory : .regular

        guard activationPolicy() != policy else { return }

        setActivationPolicy(policy)

        // A newly regular app shows its menus only once it's active.
        if policy == .regular {
            activate()
        }
    }
}
