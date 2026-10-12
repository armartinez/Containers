//
//  ImageInspect.swift
//  Containers
//
//  Created by Axel Martinez on 2026/06/06.
//

import ContainerSystem
import SwiftUI

struct ImageInspect: View {
    let image: ImageItem

    @Environment(ImageManager.self) private var imageManager

    @State private var printable: ContainerSystem.ImageResource?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let errorMessage {
                ContentUnavailableView(
                    "Inspect Unavailable",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(errorMessage)
                )
            } else {
                // Shown while loading too, empty, so its scroll view is under the toolbar from the start.
                InspectView(value: printable)
            }
        }
        .contentReady(isLoaded)
        .task(id: image.id) {
            await loadInspectDetail()
        }
    }

    /// An error is as much a result to be sized to as the detail itself.
    private var isLoaded: Bool {
        printable != nil || errorMessage != nil
    }

    private func loadInspectDetail() async {
        errorMessage = nil

        do {
            printable = try await imageManager.inspect(
                image: image.imageDescription
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
