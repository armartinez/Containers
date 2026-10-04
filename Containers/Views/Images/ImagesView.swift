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
    @Environment(ReportManager.self) private var reportManager
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
        let working = activityCenter.activities(ofKind: .image)
        var landedIDs = Set<String>()

        let landed = images.map { image -> ImageItem in
            var image = image
            // Read first: once the row carries work, its id is the work's.
            let identity = image.id

            if let activity = working.first(where: { $0.id == image.id }) {
                image.activity = ActivitySnapshot(activity)
            } else if let report = reportManager.latestReport(
                named: image.imageDescription.reference,
                ofKind: [.image, .build]
            ), !report.isRead {
                // Builds and pulls are both reported against the image.
                image.activity = ActivitySnapshot(report: report, id: identity)
            }

            landedIDs.insert(image.id)

            return image
        }

        let pending =
            working
            .filter { !landedIDs.contains($0.id) }
            .map { ImageItem(pending: ActivitySnapshot($0)) }

        return pending + landed
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

    /// One whose delete failed counts, so it can be tried again.
    private func isSettled(_ image: ImageItem) -> Bool {
        !image.isPending && (image.activity?.hasEnded ?? true)
    }

    /// Running asks for a container's settings, so it is one image at a time.
    private func runnable(_ images: [ImageItem]) -> ImageItem? {
        guard images.count == 1, let image = images.first, isSettled(image)
        else { return nil }

        return image
    }

    private var rowActions: TableRowActions<ImageItem> {
        TableRowActions(
            noun: "Image",
            name: { "\($0.name):\($0.tag)" },
            canOpen: { !$0.isPending },
            open: openDetails(for:),
            // Not an image a container was made from.
            canDelete: { image in
                image.isPending
                    ? image.activity?.hasEnded ?? true
                    : isSettled(image) && !image.isInUse
            },
            deletesWithoutAsking: \.isPending,
            delete: deleteImages,
            canStart: { runnable($0) != nil },
            start: { run(runnable($0)) },
            pendingWork: { $0.isPending ? $0.activity : nil }
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
                HStack(spacing: 4) {
                    Text(image.name)
                        .lineLimit(1)
                        .foregroundStyle(
                            image.isPending ? .secondary : .primary
                        )

                    if let activity = image.activity {
                        Spacer(minLength: 0)

                        RowProgressIndicator(
                            activity: activity,
                            activityCenter: activityCenter,
                            openReport: openWindow.report
                        )
                    }
                }
            }
            .width(min: 150, ideal: 180)

            TableColumn("Tag", value: \.tag) { image in
                Text(image.tag)
                    .lineLimit(1)
                    .foregroundStyle(image.isPending ? .secondary : .primary)
            }
            .width(min: 22, ideal: 30)

            TableColumn("Digest", value: \.indexDigest) { image in
                if !image.isPending {
                    Text(image.indexDigest.trimmedDigest)
                        .lineLimit(1)
                        .font(.system(.body, design: .monospaced))
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
            // A row that only stands for failed work is that work.
            if image.isPending, let activity = image.activity {
                activityCenter.remove(activity.id)
                continue
            }

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
