//
//  MenuBarItem.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import AppKit
import ContainerSystem
import SwiftUI

struct MenuBarItem: View {
    @Environment(SystemManager.self) var system
    @Environment(SystemActions.self) private var systemActions
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        StatusButton(status: system.status)

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

    private func button(
        for action: SystemActions.Action,
        keyEquivalent: String? = nil
    ) -> some View {
        MenuButton(
            title: systemActions.title(for: action),
            icon: systemActions.symbol(for: action),
            keyEquivalent: keyEquivalent,
            isLoading: systemActions.working == action && action != .quit,
            isDisabled: !systemActions.isEnabled(action)
        ) {
            Task {
                do {
                    try await systemActions.perform(action)
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
    let status: SystemManager.Status

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

private struct MenuButton: View {
    let title: String
    let icon: String
    var keyEquivalent: String? = nil
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 14)
                    .foregroundStyle(isDisabled ? .tertiary : .secondary)

                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(
                        isHovered && !isDisabled ? .white : .primary
                    )

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else if let keyEquivalent {
                    Text("⌘\(keyEquivalent)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        isHovered && !isDisabled
                            ? Color.accentColor.opacity(0.15) : .clear
                    )
            )
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
