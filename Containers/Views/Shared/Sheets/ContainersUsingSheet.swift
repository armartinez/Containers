//
//  ContainersUsingSheet.swift
//  Containers
//
//  Created by Axel Martinez on 16/09/2026.
//

import ContainerSystem
import SwiftUI

/// The containers an image or a volume is used by, each opening into its own
/// window.
struct ContainersUsingSheet: View {
    let title: String
    let subject: String
    let includes: (ContainerSnapshot) -> Bool

    @Environment(ContainerManager.self) private var containerManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    @SwiftUI.State private var containers: [ContainerItem] = []
    @SwiftUI.State private var selection: Set<ContainerItem.ID> = []
    @SwiftUI.State private var isLoading = true
    @SwiftUI.State private var errorAlert: ErrorAlert?

    var body: some View {
        CreateView(
            title: title,
            error: $errorAlert,
            width: 460,
            height: 340,
            contentPadding: 0,
            contentTitle: subject,
            contentTitleRule: true,
            content: {
                content
            },
            actions: {
                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .frame(width: .sheetButtonLabelWidth)
                }
                .defaultAction(enabled: true)
            }
        )
        .task {
            await loadContainers()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if containers.isEmpty {
            Text("No Containers")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(containers, selection: $selection) {
                TableColumn("Name") { container in
                    Text(container.id)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                TableColumn("Status") { container in
                    let isRunning = container.status == .running

                    Text(isRunning ? "Running" : "Stopped")
                        .rowTint(isRunning ? .green : .secondary)
                        .lineLimit(1)
                }
                .width(min: 72, ideal: 96, max: 120)
            }
            .tableStyle(.inset)
            .contextMenu(forSelectionType: ContainerItem.ID.self) { _ in
            } primaryAction: { ids in
                // A detail is opened for one container at a time.
                if ids.count == 1, let id = ids.first {
                    open(id)
                }
            }
        }
    }

    private func open(_ id: ContainerItem.ID) {
        dismiss()
        openWindow(id: ContainersApp.containerDetailWindowID, value: id)
    }

    private func loadContainers() async {
        defer { isLoading = false }

        do {
            containers = try await containerManager.list()
                .filter(includes)
                .map(ContainerItem.init)
        } catch {
            errorAlert = ErrorAlert(
                "The containers couldn’t be loaded.",
                error: error
            )
        }
    }
}
