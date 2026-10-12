//
//  ImageDetailView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/14.
//

import ContainerSystem
import Containerization
import ContainerizationOCI
import SwiftUI

struct ImageDetailWindow: View {
    @Environment(ImageManager.self) private var imageManager
    let imageReference: String

    @SwiftUI.State private var image: ImageItem?
    @SwiftUI.State private var isLoading: Bool = true
    @SwiftUI.State private var toolbarController = DetailToolbarController()

    var body: some View {
        Group {
            if let image {
                ImageDetailView(
                    image: image,
                    toolbarController: toolbarController
                )
            } else if isLoading {
                // Empty until the detail arrives; the window grows into it.
                Color.clear
                    .frame(
                        width: DetailPlaceholder.image.width,
                        height: DetailPlaceholder.image.height
                    )
            } else {
                ContentUnavailableView(
                    "Image Not Found",
                    systemImage: "cube.transparent",
                    description: Text(
                        "The image '\(imageReference)' no longer exists."
                    )
                )
                .frame(width: 550, height: 320)
            }
        }
        .background(
            DetailToolbarAttacher(
                controller: toolbarController,
                tabs: ImageDetailView.toolbarTabs,
                items: ImageDetailView.placeholderToolbarItems
            )
        )
        .navigationTitle(
            image.map { Text($0.displayName) } ?? Text("")
        )
        .task(id: imageReference) {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let items = try await imageManager.list(platform: .current)
            if let match = items.first(where: {
                $0.description.reference == imageReference
            }) {
                image = ImageItem(match)
            } else {
                image = nil
            }
        } catch {
            image = nil
        }
    }
}

struct ImageDetailView: View {
    @Environment(ImageManager.self) private var imageManager
    @Environment(ReportManager.self) private var reportManager
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openURL) private var openURL

    let image: ImageItem
    let toolbarController: DetailToolbarController

    @SwiftUI.State private var selectedCategory: DetailCategory = .history
    @SwiftUI.State private var showDeleteConfirmation: Bool = false
    @SwiftUI.State private var showCreateContainer: Bool = false
    @SwiftUI.State private var errorAlert: ErrorAlert?

    enum DetailCategory: String, CaseIterable, Hashable {
        case history
        case inspect
        case info
    }

    static var toolbarTabs: [DetailToolbarController.Tab] {
        DetailCategory.allCases.map {
            .init(title: $0.rawValue.localizedCapitalized, icon: tabIcon($0))
        }
    }

    static func tabIcon(_ tab: DetailCategory) -> String {
        switch tab {
        case .info: "info.circle"
        case .history: "clock.arrow.circlepath"
        case .inspect: "curlybraces"
        }
    }

    /// The same shape with nothing wired up, so the window can build its
    /// toolbar before it has an image to build one from.
    static var placeholderToolbarItems: [DetailToolbarItem] {
        [
            .reportsPlaceholder,
            DetailToolbarItem(id: "run", title: "Run", icon: "play.fill", isEnabled: false) {},
            DetailToolbarItem(id: "save", title: "Save", icon: "folder.fill", isEnabled: false) {},
            DetailToolbarItem(
                id: "delete",
                title: "Delete",
                icon: "trash",
                isEnabled: false
            ) {},
        ]
    }

    var body: some View {
        DetailView(
            selectedTab: $selectedCategory,
            showTabs: true,
            toolbarItems: toolbarItems,
            tabTitle: { category in
                category.rawValue.localizedCapitalized
            },
            tabIcon: { Self.tabIcon($0) },
            tabWidth: { category in
                category == .inspect ? 750 : 650
            },
            tabMaxHeight: { category in
                switch category {
                case .info: nil
                case .history: 430
                case .inspect: 500
                }
            },
            tabContentWidth: { category in
                switch category {
                case .info: 650
                case .history, .inspect: nil
                }
            },
            toolbarController: toolbarController,
            tabContent: { category in
                switch category {
                case .info:
                    ImageInfo(image: image)

                case .inspect:
                    ImageInspect(image: image)

                case .history:
                    ImageHistory(
                        imageReference: image.imageDescription.reference,
                        platform: Platform.current
                    )
                }
            }
        )
        .sheet(isPresented: $showCreateContainer) {
            CreateContainerView(
                imageReference: image.imageDescription.reference,
                mode: .run
            )
        }
        .confirmationDialog(
            "Delete Image?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteImage()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Delete \(image.displayName)? This cannot be undone."
            )
        }
        .errorAlert($errorAlert)
    }

    private var toolbarItems: [DetailToolbarItem] {
        [
            // A build and a fetch are both reported against the image they
            // were making, which is the image this window is about.
            .reports(
                about: image.imageDescription.reference,
                ofKind: [.image, .build],
                manager: reportManager,
                openURL: openURL
            ),
            DetailToolbarItem(
                id: "run",
                title: "Run",
                icon: "play.fill",
                help: "Run container"
            ) {
                showCreateContainer = true
            },
            DetailToolbarItem(
                id: "save",
                title: "Save",
                icon: "folder.fill",
                help: "Save image"
            ) {
                SaveImagePanel.present(
                    image: image.imageDescription,
                    imageManager: imageManager,
                    onError: { err in
                        self.errorAlert = ErrorAlert(
                            "The image couldn’t be saved.",
                            error: err
                        )
                    }
                )
            },
            DetailToolbarItem(
                id: "delete",
                title: "Delete",
                icon: "trash",
                help: "Delete image"
            ) {
                showDeleteConfirmation = true
            },
        ]
    }

    private func deleteImage() {
        Task {
            do {
                try await imageManager.delete(images: [image.imageDescription])
                dismissWindow(
                    id: ContainersApp.imageDetailWindowID,
                    value: image.imageDescription.reference
                )
            } catch {
                self.errorAlert = ErrorAlert(
                    "The image couldn’t be deleted.",
                    error: error
                )
            }
        }
    }
}
