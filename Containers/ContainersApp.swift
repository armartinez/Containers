//
//  ContainersApp.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/04.
//

import AppKit
import ContainersCore
import SwiftUI
import TipKit

class AppDelegate: NSObject, NSApplicationDelegate {
    // Before launch finishes, so a menu bar only app shows no Dock icon until a window opens.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(UserDefaults.appIconPlacement.activationPolicy)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.beginUpdatingActivationPolicy()
    }
}

@main
struct ContainersApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @AppStorage(UserDefaults.appIconPlacementKey) private var appIconPlacement: AppIconPlacement = .dockAndMenuBar

    @State private var containerSystem: ContainerSystem

    // MARK: Domain Managers
    @State private var containerManager = ContainerManager()
    @State private var imageManager = ImageManager()
    @State private var volumeManager = VolumeManager()
    @State private var networkManager = NetworkManager()
    @State private var reportManager: ReportManager

    // MARK: Utilities
    @State private var activityCenter: ActivityCenter
    @State private var systemActions: SystemActions

    init() {
        // ContainerSystem is initalized here to allow for testability and previews
        let containerSystem = ContainerSystem.shared
        let reportManager = ReportManager()
        let systemActions = SystemActions(containerSystem: containerSystem)

        // The dashboard asks for a mode the first time it opens.
        containerSystem.mode = UserDefaults.systemMode ?? .default
        containerSystem.resolverDirectory = UserDefaults.resolverDirectory

        _containerSystem = State(initialValue: containerSystem)
        _reportManager = State(initialValue: reportManager)
        _activityCenter = State(initialValue: ActivityCenter(reportManager: reportManager))
        _systemActions = State(initialValue: systemActions)

        do {
            try Tips.configure()
        } catch {
            print("TipKit configuration error: \(error)")
        }
    }

    static let dashboardWindowID = "dashboard"
    static let settingsWindowID = "settings"
    static let containerDetailWindowID = "container-detail"
    static let imageDetailWindowID = "image-detail"
    static let volumeDetailWindowID = "volume-detail"
    static let reportDetailWindowID = "report-detail"

    var body: some Scene {
        Window(
            "Containers",
            id: Self.dashboardWindowID,
            content: {
                DashboardView()
                    .environment(containerManager)
                    .environment(imageManager)
                    .environment(volumeManager)
                    .environment(containerSystem)
                    .environment(networkManager)
                    .environment(activityCenter)
                    .environment(reportManager)
                    .environment(systemActions)
            }
        )
        .defaultSize(width: 800, height: 520)
        .defaultPosition(.center)
        .windowResizability(.contentSize)
        // Links into the app are the dashboard's to open.
        .handlesExternalEvents(matching: ["\(AppLink.scheme)://"])

        MenuBarExtra(
            isInserted: showsMenuBarItem,
            content: {
                MenuBarItem()
                    .environment(containerSystem)
                    .environment(systemActions)
            },
            label: {
                Image(menuBarSymbol)
                    .font(.system(size: 28))
            }
        )
        .menuBarExtraStyle(.menu)

        Window("Settings", id: Self.settingsWindowID) {
            SettingsView()
                .environment(networkManager)
                .environment(containerSystem)
        }
        .defaultSize(width: 600, height: 400)
        .defaultPosition(.center)
        .handlesExternalEvents(matching: [])
        .commands { PreferencesCommands() }

        windowGroup(
            "Container Details",
            id: Self.containerDetailWindowID,
            placeholder: DetailPlaceholder.container
        ) { id in
            ContainerDetailWindow(id: id)
                .environment(containerSystem)
                .environment(networkManager)
                .environment(containerManager)
                .environment(volumeManager)
                .environment(imageManager)
                .environment(reportManager)
                .environment(activityCenter)
        }

        windowGroup(
            "Image Details",
            id: Self.imageDetailWindowID,
            placeholder: DetailPlaceholder.image
        ) { reference in
            ImageDetailWindow(imageReference: reference)
                .environment(containerSystem)
                .environment(networkManager)
                .environment(imageManager)
                .environment(containerManager)
                .environment(volumeManager)
                .environment(reportManager)
                .environment(activityCenter)
        }

        windowGroup(
            "Volume Details",
            id: Self.volumeDetailWindowID,
            placeholder: DetailPlaceholder.volume
        ) { volumeID in
            VolumeDetailWindow(id: volumeID)
                .environment(volumeManager)
                .environment(reportManager)
        }

        windowGroup(
            "Report",
            id: Self.reportDetailWindowID,
            placeholder: DetailPlaceholder.report
        ) { reportID in
            ReportDetailWindow(id: reportID)
                .environment(reportManager)
        }
    }

    /// Taking the item out of the menu bar leaves the Dock icon, so the app is never hidden from both.
    private var showsMenuBarItem: Binding<Bool> {
        Binding(
            get: { appIconPlacement.showsInMenuBar },
            set: { isShown in
                guard !isShown else { return }

                appIconPlacement = .dock
                NSApp.updateActivationPolicy()
            }
        )
    }

    /// Slashed beside the CLI, since its API server runs the containers and the app's own system is idle.
    private var menuBarSymbol: String {
        switch containerSystem.status {
        case .running: "container.stack.fill"
        case .readOnly: "container.stack.slash"
        case .starting, .stopping, .notStarted, .failed: "container.stack"
        }
    }

    /// A detail window group, keyed by the id of what it shows.
    private func windowGroup<Content: View>(
        _ title: String,
        id: String,
        placeholder: CGSize,
        @ViewBuilder content: @escaping (String) -> Content
    ) -> some Scene {
        WindowGroup(title, id: id, for: String.self) { $value in
            if let value {
                content(value)
            }
        }
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
        // Left alone, a window group opens an empty window of its own for a link meant for the dashboard.
        .handlesExternalEvents(matching: [])
        .defaultWindowPlacement { _, context in
            DetailPlaceholder.underParentToolbar(
                on: context.defaultDisplay.visibleRect,
                size: placeholder
            )
        }
        .commandsRemoved()
    }

    struct PreferencesCommands: Commands {
        @Environment(\.openWindow) private var openWindow
        var body: some Commands {
            CommandGroup(replacing: .appSettings) {
                Button {
                    openWindow(id: ContainersApp.settingsWindowID)
                } label: {
                    Label("Settings…", systemImage: "gearshape")
                }
            }
        }
    }
}
