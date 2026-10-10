//
//  ContainersView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import ContainerSystem
import SwiftUI

struct ContainersView: View {
    @Environment(ContainerManager.self) private var containerManager
    @Environment(SystemManager.self) private var system
    @Environment(VolumeManager.self) private var volumeManager
    @Environment(ActivityCenter.self) private var activityCenter
    @Environment(\.openWindow) private var openWindow

    @Binding var searchText: String
    @Binding var runningContainersOnly: Bool
    @Binding var selection: Set<ContainerItem.ID>
    @Binding var actions: SelectionActions
    @Binding var command: SelectionCommand?

    var refreshTrigger: Int

    @State private var containers: [ContainerItem] = []

    private var trimmedText: String {
        self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A container still being made gets a row of its own whatever the filter
    /// says, keyed by the name it will have, so it becomes that row in place.
    private func withCreations(
        _ containers: [ContainerItem]
    ) -> [ContainerItem] {
        activityCenter.marked(
            containers,
            ofKind: .container,
            // An unread failure from an earlier run, unless the container has
            // started since.
            reportName: { $0.status == .running ? nil : $0.id },
            reportKinds: [.container],
            pendingRow: ContainerItem.init(pending:)
        )
        .sorted { $0.id < $1.id }
    }

    private var filteredContainers: [ContainerItem] {
        if trimmedText.isEmpty {
            return withCreations(
                runningContainersOnly
                    ? containers.filter({ $0.status == .running }) : containers
            )
        }

        let filtered = self.containers.filter({
            $0.id.contains(trimmedText) == true
                || $0.imageName.contains(trimmedText)
                || $0.formattedPorts.contains(trimmedText) == true
                || $0.formattedIPAddress.contains(trimmedText) == true
        })

        return withCreations(
            runningContainersOnly
                ? filtered.filter({ $0.status == .running }) : filtered
        )
    }

    private func startable(
        _ containers: [ContainerItem]
    ) -> [ContainerItem] {
        containers.filter { !$0.isDisabled && $0.status == .stopped }
    }

    private func stoppable(
        _ containers: [ContainerItem]
    ) -> [ContainerItem] {
        containers.filter { !$0.isDisabled && $0.status == .running }
    }

    private var rowActions: TableRowActions<ContainerItem> {
        TableRowActions(
            noun: "Container",
            name: \.id,
            open: openDetails(for:),
            canDelete: { !$0.isExecuting },
            delete: deleteContainers,
            canStart: { !startable($0).isEmpty },
            start: { startContainers(startable($0)) },
            canStop: { !stoppable($0).isEmpty },
            stop: { stopContainers(stoppable($0)) },
            pendingWork: \.pendingWork
        )
    }

    var body: some View {
        TableView(
            rows: filteredContainers,
            selection: $selection,
            sortOrder: [KeyPathComparator(\.name)],
            actions: $actions,
            command: $command,
            rowActions: rowActions,
            refreshTrigger: refreshTrigger,
            tableStyle: .automatic,
            activityKind: .container,
            onClear: { containers = [] },
            onRefresh: refreshContainers,
            menu: { selected in
                Button("Start", systemImage: "play") {
                    startContainers(startable(selected))
                }
                .disabled(startable(selected).isEmpty)

                Button("Stop", systemImage: "stop") {
                    stopContainers(stoppable(selected))
                }
                .disabled(stoppable(selected).isEmpty)
            }
        ) {
            TableColumn("State", value: \.formattedState) { container in
                // The name is on the tooltip and for VoiceOver.
                Image(systemName: stateSymbol(for: container))
                    .font(.system(size: 8))
                    .rowTint(stateColor(for: container))
                    .frame(maxWidth: .infinity)
                    .help(stateLabel(for: container))
                    .accessibilityLabel(stateLabel(for: container))
            }
            .width(min: 36, ideal: 44, max: 60)

            TableColumn("Name", value: \.name) { container in
                ActivityRowName(
                    row: container,
                    activityCenter: activityCenter,
                    openReport: openWindow.report
                )
            }
            .width(min: 100, ideal: 150, max: 250)

            TableColumn("Image", value: \.imageName) { container in
                Text(container.imageName)
                    .lineLimit(1)
                    .rowForeground(for: container)
            }
            .width(min: 120, ideal: 180, max: 300)

            TableColumn("IP Address", value: \.formattedIPAddress) { container in
                Text(
                    !container.isPending
                        ? container.formattedIPAddress : "—"
                )
                .lineLimit(1)
                .font(.system(.body, design: .monospaced))
                .rowForeground(for: container, isDimmed: !container.hasIPAddress)
                .textSelection(.enabled)
            }
            .width(min: 100, ideal: 120, max: 140)

            TableColumn("Uptime", value: \.startedSort) { container in
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    Text(
                        !container.isPending
                            ? container.formattedUptime(at: context.date) : "—"
                    )
                    .lineLimit(1)
                    .font(.system(.body, design: .monospaced))
                    .rowForeground(for: container, isDimmed: container.status != .running)
                }
            }
            .width(min: 80, ideal: 100, max: 140)
        }
        .onChange(of: containerManager.lastContainerChange) {
            Task {
                guard system.status == .running else { return }
                try? await refreshContainers()
            }
        }
    }

    private func openDetails(for container: ContainerItem) {
        openWindow(
            id: ContainersApp.containerDetailWindowID,
            value: container.id
        )
    }

    /// Unknown gets its own mark: it shares the stopped colour, and a hollow
    /// ring would pass it off as stopped.
    private func stateSymbol(for container: ContainerItem) -> String {
        switch container.status {
        case .starting, .running, .stopping: "circle.fill"
        case .stopped: "circle"
        case .unknown: "questionmark.circle"
        }
    }

    private func stateLabel(for container: ContainerItem) -> String {
        container.status == .unknown
            ? "Unknown" : container.status.rawValue.localizedCapitalized
    }

    private func stateColor(for container: ContainerItem) -> Color {
        switch container.status {
        case .running: return .green
        case .starting, .stopping: return .orange
        case .stopped: return .secondary
        case .unknown: return .secondary
        }
    }

    /// Run as row work, so a failure shows in the row like a creation's.
    private func startContainers(_ containers: [ContainerItem]) {
        let containerManager = containerManager

        for container in containers {
            activityCenter.run(
                on: container.id,
                kind: .container,
                subtitle: container.imageName,
                failureTitle: "The container couldn’t be started.",
                // The state dot shows it.
                showsProgress: false
            ) {
                try await containerManager.run(id: container.id)
            }
        }
    }

    private func stopContainers(_ containers: [ContainerItem]) {
        let containerManager = containerManager
        let timeout = Int32(UserDefaults.stopContainerTimeoutSeconds)

        for container in containers {
            activityCenter.run(
                on: container.id,
                kind: .container,
                subtitle: container.imageName,
                failureTitle: "The container couldn’t be stopped.",
                // The state dot shows it.
                showsProgress: false
            ) {
                try await containerManager.stop(
                    ids: [container.id],
                    timeoutSeconds: timeout
                )
            }
        }
    }

    private func deleteContainers(_ containers: [ContainerItem]) {
        let containerManager = containerManager

        for container in containers {
            activityCenter.run(
                on: container.id,
                kind: .container,
                subtitle: container.imageName,
                failureTitle: "The container couldn’t be deleted."
            ) {
                try await containerManager.delete(
                    ids: [container.id],
                    force: true
                )
            }
        }
    }

    private func refreshContainers() async throws {
        containers = try await containerManager.list().map(ContainerItem.init)
    }
}

#Preview {
    let reportManager = ReportManager()

    ContainersView(
        searchText: .constant(""),
        runningContainersOnly: .constant(false),
        selection: .constant([]),
        actions: .constant(SelectionActions()),
        command: .constant(nil),
        refreshTrigger: 0
    )
    .environment(ContainerManager())
    .environment(SystemManager())
    .environment(ActivityCenter(reports: reportManager))
    .environment(reportManager)
}
