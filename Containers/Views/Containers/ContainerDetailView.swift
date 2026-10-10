//
//  ContainerDetailView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import ContainerSystem
import Containerization
import ContainerizationOCI
import SwiftUI

struct ContainerDetailWindow: View {
    @Environment(ContainerManager.self) private var containerManager

    let id: String

    @SwiftUI.State private var snapshot: ContainerSnapshot?
    @SwiftUI.State private var isLoading: Bool = true
    @SwiftUI.State private var loadError: Error?
    @SwiftUI.State private var toolbarController = DetailToolbarController()

    var body: some View {
        Group {
            if let snapshot {
                ContainerDetailView(
                    container: ContainerItem(snapshot),
                    initialSnapshot: snapshot,
                    toolbarController: toolbarController
                )
            } else if isLoading {
                // Empty until the detail arrives; the window grows into it.
                Color.clear
                    .frame(
                        width: DetailPlaceholder.container.width,
                        height: DetailPlaceholder.container.height
                    )
            } else {
                ContentUnavailableView(
                    "Container Not Found",
                    systemImage: "shippingbox",
                    description: Text(
                        loadError?.localizedDescription
                            ?? "The container '\(id)' no longer exists."
                    )
                )
                .frame(width: 550, height: 320)
            }
        }
        .background(
            DetailToolbarAttacher(
                controller: toolbarController,
                tabs: ContainerDetailView.toolbarTabs,
                items: ContainerDetailView.placeholderToolbarItems
            )
        )
        .navigationTitle(id)
        .task(id: id) {
            await load()
        }
    }

    private func load() async {
        isLoading = true

        defer { isLoading = false }

        do {
            snapshot = try await containerManager.get(id: id)
            loadError = nil
        } catch {
            snapshot = nil
            loadError = error
        }
    }
}

struct ContainerDetailView: View {
    @Environment(ContainerManager.self) private var containerManager
    @Environment(ActivityCenter.self) private var activityCenter
    @Environment(ReportManager.self) private var reportManager
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openURL) private var openURL

    @SwiftUI.State private var container: ContainerItem
    @SwiftUI.State private var snapshot: ContainerSnapshot?
    @SwiftUI.State private var status: ContainerStatus
    /// Opens on the logs, which is usually why the window was opened.
    @SwiftUI.State private var selectedCategory: DetailCategory = .logs
    @SwiftUI.State private var errorAlert: ErrorAlert?
    @SwiftUI.State private var showDeleteConfirmation = false
    @SwiftUI.State private var isLoadingSnapshot = false
    @SwiftUI.State private var isOperationInProgress = false

    enum DetailCategory: String, CaseIterable, Hashable {
        case logs
        case inspect
        case info
    }

    let toolbarController: DetailToolbarController

    init(
        container: ContainerItem,
        initialSnapshot: ContainerSnapshot? = nil,
        toolbarController: DetailToolbarController = DetailToolbarController()
    ) {
        self.toolbarController = toolbarController

        let initialContainer =
            initialSnapshot.map(ContainerItem.init) ?? container

        self._container = State(initialValue: initialContainer)
        self._snapshot = State(initialValue: initialSnapshot)
        self._status = State(initialValue: initialContainer.status)
    }

    var body: some View {
        DetailView(
            selectedTab: $selectedCategory,
            toolbarItems: toolbarItems,
            tabTitle: { tab in
                tab.rawValue.localizedCapitalized
            },
            tabIcon: { Self.tabIcon($0) },
            tabMaxHeight: { tab in
                switch tab {
                case .info: nil
                case .logs: 450
                case .inspect: 450
                }
            },
            tabContentWidth: { tab in
                switch tab {
                case .info: DetailPlaceholder.width
                case .logs, .inspect: nil
                }
            },
            toolbarController: toolbarController,
            tabContent: { tab in
                switch tab {
                case .info:
                    snapshotContent { snapshot in
                        ContainerInfo(snapshot: snapshot)
                    }
                case .inspect:
                    snapshotContent { snapshot in
                        ContainerInspect(snapshot: snapshot)
                    }
                case .logs:
                    ContainerLogs(containerID: container.id)
                }
            }
        )
        .task(id: container.id) {
            guard snapshot == nil else { return }
            await refreshSnapshot()
        }
        .errorAlert($errorAlert)
        .confirmationDialog(
            "Delete Container",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await containerManager.delete(
                            ids: [container.id],
                            force: true
                        )

                        errorAlert = nil
                        dismissWindow(
                            id: ContainersApp.containerDetailWindowID,
                            value: container.id
                        )
                    } catch {
                        self.errorAlert = ErrorAlert(
                            "The container couldn’t be deleted.",
                            error: error
                        )
                    }
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Are you sure you want to delete container '\(container.id)'? This action cannot be undone."
            )
        }
        .onChange(of: containerManager.lastContainerChange) {
            Task {
                await refreshSnapshot()
            }
        }
    }

    private func snapshotContent<Content: View>(
        @ViewBuilder content: (ContainerSnapshot) -> Content
    ) -> some View {
        Group {
            if let snapshot {
                content(snapshot)
            } else if isLoadingSnapshot {
                // The window stays hidden until ready.
                Color.clear
            } else {
                ContentUnavailableView(
                    "Container Details Unavailable",
                    systemImage: "shippingbox",
                    description: Text(
                        "The full container snapshot could not be loaded."
                    )
                )
            }
        }
        // Outermost, or the window can't read it. A failed load still counts
        // as ready, so the window sizes to the error.
        .contentReady(!isLoadingSnapshot || snapshot != nil)
    }

    /// Always the same items in the same order, since the toolbar is built before the
    /// snapshot arrives and changing the set would rebuild it visibly. Only titles,
    /// actions and enabled states change.
    private var toolbarItems: [DetailToolbarItem] {
        let busy = isOperationInProgress || activityCenter.isWorking(on: container.id)
        let isRunning = status == .running
        let isStopped = status == .stopped

        return [
            .reports(
                about: container.id,
                ofKind: [.container],
                manager: reportManager,
                openURL: openURL
            ),
            DetailToolbarItem(
                id: "run",
                title: isRunning ? "Stop" : "Start",
                icon: isRunning ? "stop.fill" : "play.fill",
                help: isRunning ? "Stop container" : "Start container",
                isEnabled: !busy && (isRunning || isStopped)
            ) {
                if isRunning {
                    stopContainer()
                } else {
                    runContainer()
                }
            },
            DetailToolbarItem(
                id: "delete",
                title: "Delete",
                icon: "trash",
                help: "Delete container",
                isEnabled: !busy
            ) {
                showDeleteConfirmation = true
            },
        ]
    }

    /// The same items, inert, so the toolbar can be built before the container loads.
    static var placeholderToolbarItems: [DetailToolbarItem] {
        [
            .reportsPlaceholder,
            DetailToolbarItem(
                id: "run",
                title: "Start",
                icon: "play.fill",
                isEnabled: false
            ) {},
            DetailToolbarItem(
                id: "delete",
                title: "Delete",
                icon: "trash",
                isEnabled: false
            ) {},
        ]
    }

    static var toolbarTabs: [DetailToolbarController.Tab] {
        DetailCategory.allCases.map {
            .init(title: $0.rawValue.localizedCapitalized, icon: tabIcon($0))
        }
    }

    static func tabIcon(_ tab: DetailCategory) -> String {
        switch tab {
        case .info: "info.circle"
        case .logs: "list.bullet.rectangle"
        case .inspect: "curlybraces"
        }
    }

    private func refreshSnapshot() async {
        isLoadingSnapshot = snapshot == nil
        defer {
            isLoadingSnapshot = false
        }

        do {
            let updatedSnapshot = try await containerManager.get(
                id: container.id
            )
            let updatedContainer = ContainerItem(updatedSnapshot)

            snapshot = updatedSnapshot
            container = updatedContainer
            status = updatedContainer.status
            errorAlert = nil
        } catch {
            self.errorAlert = ErrorAlert(
                "The container couldn’t be refreshed.",
                error: error
            )
        }
    }

    /// Runs through the activity center, so progress and failures show on the
    /// container's dashboard row.
    private func runContainer() {
        let containerManager = containerManager
        let id = container.id

        activityCenter.run(
            on: id,
            kind: .container,
            subtitle: container.imageName,
            failureTitle: "The container couldn’t be started.",
            showsProgress: false
        ) {
            try await containerManager.run(id: id)
        }
    }

    private func stopContainer() {
        let containerManager = containerManager
        let id = container.id
        let timeout = UserDefaults.stopContainerTimeoutSeconds

        activityCenter.run(
            on: id,
            kind: .container,
            subtitle: container.imageName,
            failureTitle: "The container couldn’t be stopped.",
            showsProgress: false
        ) {
            try await containerManager.stop(ids: [id], timeoutSeconds: timeout)
        }
    }
}

#Preview {
    let reportManager = ReportManager()

    ContainerDetailView(
        container: ContainerItem(
            ContainerSnapshot(
                configuration: ContainerConfiguration(
                    id: "preview-container",
                    image: ImageDescription(
                        reference: "nginx:latest",
                        descriptor: ContainerizationOCI.Descriptor(
                            mediaType:
                                "application/vnd.oci.image.manifest.v1+json",
                            digest: "sha256:1234567890abcdef",
                            size: 1024
                        )
                    ),
                    process: ProcessConfiguration(
                        executable: "/bin/sh",
                        arguments: [],
                        environment: [],
                        workingDirectory: "/",
                        terminal: false
                    )
                ),
                status: .running,
                networks: [],
                startedDate: Date()
            )
        )
    )
    .frame(width: 550)
    .environment(ContainerManager())
    .environment(ActivityCenter(reports: reportManager))
    .environment(reportManager)
}
