//
//  ImagesView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import ContainerSystem
import Containerization
import ContainerizationOCI
import SwiftUI
import TipKit

struct ImagesView: View {
    @Environment(ImageManager.self) private var imageManager
    @Environment(ActivityCenter.self) private var activityCenter
    @Environment(\.openWindow) private var openWindow

    @Binding var searchText: String
    @Binding var selection: Set<ImageItem.ID>
    @Binding var actions: SelectionActions
    @Binding var command: SelectionCommand?

    var refreshTrigger: Int

    private let runContainerTip = RunContainerTip()

    @SwiftUI.State private var images: [ImageItem] = []
    @SwiftUI.State private var imageToRun: ImageItem? = nil

    private var trimmedText: String {
        self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// An image still on its way gets a row of its own, keyed by the reference
    /// it will have, so it becomes that row in place when it lands.
    private var allImages: [ImageItem] {
        activityCenter.marked(
            images,
            ofKind: .image,
            // Builds and pulls are both reported against the image.
            reportName: { $0.imageDescription.reference },
            reportKinds: [.image, .build],
            pendingRow: ImageItem.init(pending:)
        )
    }

    private var filteredImages: [ImageItem] {
        let all = allImages

        if trimmedText.isEmpty {
            return all
        }

        let filtered = all.filter({
            $0.name.contains(trimmedText) || $0.tag.contains(trimmedText)
        })

        return filtered
    }

    /// Running asks for a container's settings, so it is one image at a time.
    private func runnable(_ images: [ImageItem]) -> ImageItem? {
        guard images.count == 1, let image = images.first, !image.isDisabled
        else { return nil }

        return image
    }

    private var rowActions: TableRowActions<ImageItem> {
        TableRowActions(
            noun: "Image",
            name: \.displayName,
            open: openDetails(for:),
            // Not an image a container was made from.
            canDelete: { !$0.isExecuting && ($0.isPending || !$0.isInUse) },
            delete: deleteImages,
            canStart: { runnable($0) != nil },
            start: { run(runnable($0)) },
            pendingWork: \.pendingWork
        )
    }

    var body: some View {
        TableView(
            rows: filteredImages,
            selection: $selection,
            sortOrder: [KeyPathComparator(\.name), KeyPathComparator(\.tag)],
            actions: $actions,
            command: $command,
            rowActions: rowActions,
            refreshTrigger: refreshTrigger,
            activityKind: .image,
            onClear: { images = [] },
            onRefresh: listImages,
            menu: { selected in
                Button("Run Container…", systemImage: "play") {
                    run(runnable(selected))
                }
                .disabled(runnable(selected) == nil)
            }
        ) {
            TableColumn("Name", value: \.name) { image in
                ActivityRowName(
                    row: image,
                    activityCenter: activityCenter,
                    openReport: openWindow.report
                )
            }
            .width(min: 150, ideal: 180)

            TableColumn("Tag", value: \.tag) { image in
                if image.hasTag {
                    Text(image.tag)
                        .lineLimit(1)
                        .rowForeground(for: image)
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 22, ideal: 30)

            TableColumn("Digest", value: \.indexDigest) { image in
                if !image.isPending {
                    Text(image.indexDigest.trimmedDigest)
                        .lineLimit(1)
                        .font(.system(.body, design: .monospaced))
                        .rowForeground(for: image)
                        .textSelection(.enabled)
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 150, ideal: 200, max: 250)
        }
        .sheet(
            item: $imageToRun,
            onDismiss: {
                Task { try? await listImages() }
            },
            content: { image in
                CreateContainerView(
                    imageReference: image.imageDescription.reference,
                    mode: .run
                )
            }
        )
    }

    private func openDetails(for image: ImageItem) {
        openWindow(
            id: ContainersApp.imageDetailWindowID,
            value: image.imageDescription.reference
        )
    }

    private func run(_ image: ImageItem?) {
        guard let image else { return }

        runContainerTip.invalidate(reason: .actionPerformed)
        imageToRun = image
    }

    /// Run as row work, so a failure shows in the row like a pull's.
    private func deleteImages(_ images: [ImageItem]) {
        let imageManager = imageManager

        for image in images {
            let description = image.imageDescription

            activityCenter.run(
                on: image.id,
                kind: .image,
                failureTitle: "The image couldn’t be deleted."
            ) {
                try await imageManager.delete(images: [description])
            }
        }
    }

    func listImages() async throws {
        images = try await imageManager.list(platform: .current)
            .map(ImageItem.init)
    }
}

#Preview {
    let reportManager = ReportManager()

    ImagesView(
        searchText: .constant(""),
        selection: .constant([]),
        actions: .constant(SelectionActions()),
        command: .constant(nil),
        refreshTrigger: 0
    )
    .environment(ContainerManager())
    .environment(ActivityCenter(reports: reportManager))
    .environment(reportManager)
}
