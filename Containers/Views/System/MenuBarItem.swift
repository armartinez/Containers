//
//  MenuBarItem.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import AppKit
import ContainersCore
import SwiftUI

struct MenuBarItem: View {
    @Environment(ContainerSystem.self) var containerSystem
    @Environment(SystemActions.self) private var systemActions
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            StatusButton(status: containerSystem.status)

            Divider()

            MenuButton(
                title: "Dashboard",
                icon: "square.grid.2x2",
                keyEquivalent: "d"
            ) {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: ContainersApp.dashboardWindowID)
            }

            MenuButton(
                title: "Settings",
                icon: "gearshape",
                keyEquivalent: ","
            ) {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: ContainersApp.settingsWindowID)
            }

            Divider()

            button(for: .toggle)
            button(for: .reload)

            Divider()

            button(for: .quit, keyEquivalent: "q")
        }
        // A menu shows a label's icon only when asked to; macOS 27 hides it otherwise.
        .labelStyle(.titleAndIcon)
    }

    private func button(
        for action: SystemActions.Action,
        keyEquivalent: String? = nil
    ) -> some View {
        MenuButton(
            title: systemActions.title(for: action),
            icon: systemActions.symbol(for: action),
            keyEquivalent: keyEquivalent,
            isDisabled: !systemActions.isEnabled(action)
        ) {
            Task {
                do throws(SystemActions.Failure) {
                    try await systemActions.perform(action)

                    // The kernel is asked about in the dashboard's setup sheet.
                    if systemActions.isAskingForKernel {
                        openWindow(id: ContainersApp.dashboardWindowID)
                    }
                } catch  where error.underlying is SystemActions.CLIRunningError {
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = error.title
                    alert.informativeText = error.underlying.localizedDescription
                    alert.runModal()
                } catch {
                    // Shown in the dashboard, where the system can be looked at.
                    openWindow(id: ContainersApp.dashboardWindowID)
                }
            }
        }
    }
}

// MARK: - Status Button Component

private struct StatusButton: View {
    let status: ContainerSystem.Status

    /// A `Label`, since AppKit lays out a menu item's image and title itself. Only the
    /// symbol is coloured; AppKit fades a disabled item's text far more than its image.
    var body: some View {
        Label {
            Text(status.menuMessage)
        } icon: {
            Image(nsImage: symbol)
                .renderingMode(.original)
        }
    }

    /// Painted here and marked non-template, or AppKit tints it in the menu's text colour.
    private var symbol: NSImage {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: NSFont.menuFont(ofSize: 0).pointSize,
            weight: .regular
        )
        .applying(NSImage.SymbolConfiguration(paletteColors: [tint]))

        let image = NSImage(
            systemSymbolName: status.symbol,
            accessibilityDescription: status.message
        )?
        .withSymbolConfiguration(configuration)

        image?.isTemplate = false

        return image ?? NSImage()
    }

    /// Resolved against the app's appearance, since a dynamic colour read outside a window doesn't follow it.
    private var tint: NSColor {
        var resolved = status.nsColor

        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = status.nsColor.usingColorSpace(.sRGB) ?? status.nsColor
        }

        return resolved
    }
}

// MARK: - Menu Button Component

/// A native menu item: its icon from the label, its shortcut drawn by AppKit.
private struct MenuButton: View {
    let title: String
    let icon: String
    var keyEquivalent: String? = nil
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
        }
        .keyboardShortcut(keyEquivalent.flatMap(\.first).map { KeyboardShortcut(KeyEquivalent($0)) })
        .disabled(isDisabled)
    }
}
