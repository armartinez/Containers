//
//  VolumeDetailWindow.swift
//  Containers
//
//  Created by Axel Martinez on 03/10/2026.
//

import ContainerSystem
import SwiftUI

struct VolumeDetailWindow: View {
    @Environment(VolumeManager.self) private var volumeManager

    let id: String

    @SwiftUI.State private var volume: VolumeItem?
    @SwiftUI.State private var isLoading: Bool = true
    @SwiftUI.State private var toolbarController = DetailToolbarController()

    var body: some View {
        Group {
            if let volume {
                VolumeDetailView(
                    volume: volume,
                    toolbarController: toolbarController
                )
            } else if isLoading {
                // Empty until the detail arrives; the window grows into it.
                Color.clear
                    .frame(
                        width: DetailPlaceholder.volume.width,
                        height: DetailPlaceholder.volume.height
                    )
            } else {
                ContentUnavailableView(
                    "Volume Not Found",
                    systemImage: "externaldrive",
                    description: Text(
                        "The volume '\(id)' no longer exists."
                    )
                )
                .frame(width: 550, height: 320)
            }
        }
        .background(
            DetailToolbarAttacher(
                controller: toolbarController,
                tabs: VolumeDetailView.toolbarTabs,
                items: VolumeDetailView.placeholderToolbarItems
            )
        )
        .navigationTitle(volume.map { Text($0.name) } ?? Text(""))
        .task(id: id, load)
    }

    private func load() async {
        isLoading = true

        defer { isLoading = false }

        do {
            let summaries = try await volumeManager.summaries()
            if let match = summaries.first(where: { $0.volume.id == id }) {
                self.volume = VolumeItem(match)
            } else {
                self.volume = nil
            }
        } catch {
            self.volume = nil
        }
    }
}
