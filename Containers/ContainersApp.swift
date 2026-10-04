//
//  ContainersApp.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/04.
//

import AppKit
import ContainerSystem
import SwiftUI
import TipKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start with dock icon showing since dashboard opens on launch
        NSApp.setActivationPolicy(.regular)

        // Observe window close notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    @objc func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        // Check if this is the dashboard window by title
        if window.title == "Containers" {
            // Hide dock icon immediately when dashboard closes
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

@main
struct ContainersApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // MARK: Domain Managers
    @State private var containerManager = ContainerManager()
    @State private var imageManager = ImageManager()
    @State private var volumeManager = VolumeManager()
    @State private var networkManager = NetworkManager()
    @State private var reportManager: ReportManager
    @State private var systemManager: SystemManager

    // MARK: Utilities
    @State private var activityCenter: ActivityCenter
    @State private var systemActions: SystemActions

    init() {
        let systemManager = SystemManager()
        let reportManager = ReportManager()

        _systemManager = State(initialValue: systemManager)
        _reportManager = State(initialValue: reportManager)
        _activityCenter = State(initialValue: ActivityCenter(reports: reportManager))
        _systemActions = State(initialValue: SystemActions(manager: systemManager))

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
                    .environment(systemManager)
                    .environment(networkManager)
                    .environment(activityCenter)
                    .environment(reportManager)
                    .environment(systemActions)
                    .onAppear {
                        // Show dock icon when dashboard appears
                        NSApp.setActivationPolicy(.regular)
                    }
            }
        )
        .defaultSize(width: 800, height: 520)
        .defaultPosition(.center)
        .windowResizability(.contentSize)
        // Links into the app are the dashboard's to open.
        .handlesExternalEvents(matching: ["\(AppLink.scheme)://"])

        MenuBarExtra(
            content: {
                MenuBarItem()
                    .environment(systemManager)
                    .environment(systemActions)
            },
            label: {
                Image(
                    systemManager.status == .running
                        ? "container.stack.fill" : "container.stack"
                )
                .font(.system(size: 28))
            }
        )
        .menuBarExtraStyle(.menu)

        Window("Settings", id: Self.settingsWindowID) {
            SettingsView()
                .environment(networkManager)
                .environment(systemManager)
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
                .environment(imageManager)
                .environment(containerManager)
                .environment(volumeManager)
                .environment(activityCenter)
                .environment(reportManager)
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
                    Label("Settings...", systemImage: "gearshape")
                }
            }
        }
    }
}
