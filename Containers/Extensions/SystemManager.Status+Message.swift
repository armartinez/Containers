//
//  SystemManager.Status+Message.swift
//  Containers
//
//  Created by Axel Martinez on 17/09/2026.
//

import AppKit
import ContainerSystem
import SwiftUI

extension SystemManager.Status {
    var message: String {
        switch self {
        case .running: "System running"
        case .starting: "Starting system..."
        case .stopping: "Stopping system..."
        case .notStarted: "System stopped"
        case .failed: "System failed to start"
        }
    }

    /// Names the system, since the menu bar has no window around it to say which.
    var menuMessage: String {
        switch self {
        case .running: "Container System is running"
        case .starting: "Container System is starting…"
        case .stopping: "Container System is stopping…"
        case .notStarted: "Container System is stopped"
        case .failed: "Container System failed to start"
        }
    }

    /// Stopped and failed share a symbol; the colour tells them apart.
    var symbol: String {
        switch self {
        case .running: "gauge.with.dots.needle.100percent"
        case .starting: "gauge.with.dots.needle.33percent"
        case .stopping: "gauge.with.dots.needle.67percent"
        case .notStarted, .failed: "gauge.with.dots.needle.0percent"
        }
    }

    /// Darkened in light mode, where the system green reads faintly as text.
    private static let runningGreen = NSColor(name: nil) { appearance in
        let isDark =
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua

        return isDark
            ? .systemGreen
            : NSColor.systemGreen.blended(withFraction: 0.3, of: .black)
                ?? .systemGreen
    }

    /// An `NSColor`, since AppKit paints the menu bar icon.
    var nsColor: NSColor {
        switch self {
        case .running: Self.runningGreen
        case .starting, .stopping: .systemOrange
        // Grey, not red: a system asked to stop is not a fault.
        case .notStarted: .secondaryLabelColor
        case .failed: .systemRed
        }
    }

    var color: Color {
        Color(nsColor: nsColor)
    }
}
