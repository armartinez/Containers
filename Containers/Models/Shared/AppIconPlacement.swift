//
//  AppIconPlacement.swift
//  Containers
//
//  Created by Axel Martinez on 2026/10/30.
//

import AppKit

/// Where the app shows its icon. There's no choice without either, which would leave no way back into the app.
enum AppIconPlacement: String, CaseIterable, Identifiable {
    case dockAndMenuBar
    case dock
    case menuBar

    var id: Self { self }

    var title: String {
        switch self {
        case .dockAndMenuBar: "Dock and Menu Bar"
        case .dock: "Dock Only"
        case .menuBar: "Menu Bar Only"
        }
    }

    var showsInMenuBar: Bool {
        self != .dock
    }

    var activationPolicy: NSApplication.ActivationPolicy {
        self == .menuBar ? .accessory : .regular
    }
}
