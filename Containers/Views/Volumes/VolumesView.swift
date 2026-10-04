//
//  VolumesView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import ContainerSystem
import SwiftUI

struct VolumesView: View {
    @Environment(VolumeManager.self) private var volumeManager
    @Environment(ActivityCenter.self) private var activityCenter
    @Environment(ReportManager.self) private var reportManager
    @Environment(\.openWindow) private var openWindow

    @Binding var searchText: String
    @Binding var selection: Set<VolumeItem.ID>
    @Binding var actions: SelectionActions
    @Binding var command: SelectionCommand?

    var refreshTrigger: Int

    @State private var volumes: [VolumeItem] = []

    private var trimmedText: String {
        self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredVolumes: [VolumeItem] {
        if trimmedText.isEmpty {
            return marked(volumes)
        }
        let filtered = self.volumes.filter({
            $0.name.contains(trimmedText)
        })

        return marked(filtered)
    }

    /// Attaches each volume's work, or an unread failure from an earlier run.
    private func marked(_ volumes: [VolumeItem]) -> [VolumeItem] {
        volumes.map { volume in
            var volume = volume

            if let activity = activityCenter.activities(ofKind: .volume).first(
                where: { $0.id == volume.id }
            ) {
                volume.activity = ActivitySnapshot(activity)
            } else if let report = reportManager.latestReport(
                named: volume.id,
                ofKind: [.volume]
            ), !report.isRead {
                volume.activity = ActivitySnapshot(report: report)
            }

            return volume
        }
    }

    private var rowActions: TableRowActions<VolumeItem> {
        TableRowActions(
            noun: "Volume",
            name: \.name,
            open: openDetails(for:),
            // Not a volume a container is using.
            canDelete: { ($0.activity?.hasEnded ?? true) && !$0.isInUse },
            delete: deleteVolumes
        )
    }

    var body: some View {
        TableView(
            rows: filteredVolumes,
            selection: $selection,
            sortOrder: [KeyPathComparator(\.name)],
            actions: $actions,
            command: $command,
            rowActions: rowActions,
            refreshTrigger: refreshTrigger,
            activityKind: .volume,
            onClear: clearVolumes,
            onRefresh: listVolumes
        ) {
            TableColumn("Name", value: \.name) { volume in
                HStack(spacing: 4) {
                    Text(volume.name)
                        .lineLimit(1)

                    if let activity = volume.activity {
                        Spacer(minLength: 0)

                        RowProgressIndicator(
                            activity: activity,
                            activityCenter: activityCenter,
                            openReport: openWindow.report
                        )
                    }
                }
            }
            .width(min: 40, ideal: 40)

            TableColumn("Type", value: \.typeText) { volume in
                Text(volume.volumeType.rawValue)
            }
            .width(80)

            TableColumn("State", value: \.stateText) { volume in
                Group {
                    if volume.isInUse {
                        Text("In use")
                    } else {
                        Text("Unused")
                    }
                }
                .lineLimit(1)
            }
            .width(64)

            TableColumn("Size", value: \.sizeSort) { volume in
                if let size = volume.formattedSize {
                    Text(size)
                } else {
                    Text("Not Specified")
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 80, ideal: 80, max: 120)

            TableColumn("Created", value: \.createdAt) { volume in
                Text(volume.formattedCreated)
            }
            .width(min: 140, ideal: 180, max: 220)
        }
    }

    private func clearVolumes() {
        volumes = []
    }

    private func openDetails(for volume: VolumeItem) {
        openWindow(id: ContainersApp.volumeDetailWindowID, value: volume.id)
    }

    private func deleteVolumes(_ volumes: [VolumeItem]) {
        let volumeManager = volumeManager

        for volume in volumes {
            let item = volume.volume

            activityCenter.run(
                on: volume.id,
                kind: .volume,
                failureTitle: "The volume couldn’t be deleted."
            ) {
                try await volumeManager.delete(volumes: [item])
            }
        }
    }

    func listVolumes() async throws {
        volumes = try await volumeManager.summaries()
            .map(VolumeItem.init)
    }
}
