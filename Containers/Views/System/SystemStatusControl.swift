//
//  SystemStatusControl.swift
//  Containers
//
//  Created by Axel Martinez on 17/09/2026.
//

import AppKit
import ContainerSystem
import SwiftUI

/// The system's status; clicking it opens the same actions as the menu bar item.
struct SystemStatusControl: View {
    @Environment(SystemManager.self) private var system
    @Environment(SystemActions.self) private var systemActions
    @Environment(\.openWindow) private var openWindow

    @Binding var errorAlert: ErrorAlert?

    @State private var isHovering = false
    @State private var anchor = MenuAnchor.Holder()
    @State private var target = MenuTarget()

    var body: some View {
        Button(action: showMenu) {
            HStack(spacing: 4) {
                Image(systemName: system.status.symbol)
                    .foregroundStyle(system.status.color)
                    .frame(width: 13)

                Text(system.status.message)
                    .foregroundStyle(system.status.color)
            }
            .overlay(alignment: .trailing) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .alignmentGuide(.trailing) { $0[HorizontalAlignment.center] - 7.5 }
                    .opacity(isHovering ? 1 : 0)
            }
            .font(.subheadline)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(MenuAnchor(anchor: anchor))
        .onContinuousHover { phase in
            switch phase {
            case .active: isHovering = true
            case .ended: isHovering = false
            }
        }
        .onDisappear { isHovering = false }
    }

    /// Opens upwards, since the status bar is at the bottom of the window.
    private func showMenu() {
        guard let view = anchor.view else { return }

        // Settings is a regular window, not a Settings scene, so `openSettings` can't open it.
        target.onSettings = {
            openWindow(id: ContainersApp.settingsWindowID)
        }
        target.onToggle = { perform(.toggle) }
        target.onReload = { perform(.reload) }
        target.onQuit = { perform(.quit) }

        let menu = NSMenu()
        // Enabled states are set per item; AppKit's validation has nothing to ask here.
        menu.autoenablesItems = false
        menu.items = [
            item("Settings", symbol: "gearshape", action: #selector(MenuTarget.settings)),
            .separator(),
            item(for: .toggle, action: #selector(MenuTarget.toggle)),
            item(for: .reload, action: #selector(MenuTarget.reload)),
            .separator(),
            item(for: .quit, action: #selector(MenuTarget.quit)),
        ]

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: view.bounds.maxY + menu.size.height),
            in: view
        )
    }

    private func item(
        for systemAction: SystemActions.Action,
        action: Selector
    ) -> NSMenuItem {
        item(
            systemActions.title(for: systemAction),
            symbol: systemActions.symbol(for: systemAction),
            action: action,
            isEnabled: systemActions.isEnabled(systemAction)
        )
    }

    private func item(
        _ title: String,
        symbol: String,
        action: Selector,
        isEnabled: Bool = true
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        item.isEnabled = isEnabled
        item.target = target
        return item
    }

    private func perform(_ action: SystemActions.Action) {
        Task {
            do throws(SystemActions.Failure) {
                try await systemActions.perform(action)
            } catch {
                errorAlert = ErrorAlert(error.title, error: error.underlying)
            }
        }
    }

    /// Provides the view the menu pops up from.
    private struct MenuAnchor: NSViewRepresentable {
        @MainActor final class Holder {
            weak var view: NSView?
        }

        let anchor: Holder

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            anchor.view = view
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            anchor.view = nsView
        }
    }

    /// An `NSMenu` sends to a target, which a struct cannot be.
    @MainActor private final class MenuTarget: NSObject {
        var onSettings: () -> Void = {}
        var onToggle: () -> Void = {}
        var onReload: () -> Void = {}
        var onQuit: () -> Void = {}

        @objc func settings() { onSettings() }
        @objc func toggle() { onToggle() }
        @objc func reload() { onReload() }
        @objc func quit() { onQuit() }
    }
}
