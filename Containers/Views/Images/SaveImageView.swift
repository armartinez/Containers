//
//  SaveImageView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import AppKit
import ContainerSystem
import Containerization
import ContainerizationOCI
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum SaveImagePanel {
    static func present(
        image: ImageDescription,
        imageManager: ImageManager,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        let panel = NSSavePanel()
        panel.title = "Save Image"
        panel.message = "Save the image as an OCI compatible tar archive."
        panel.nameFieldStringValue = defaultFilename(for: image)
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "tar")
        ].compactMap { $0 }

        let selection = SavePlatformSelection()
        let accessory = NSHostingView(
            rootView: SavePanelAccessoryView(selection: selection)
        )
        accessory.frame = NSRect(x: 0, y: 0, width: 380, height: 44)
        panel.accessoryView = accessory

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }
        let platform = selection.value.platform ?? .current

        Task { @MainActor in
            do {
                try await imageManager.save(
                    images: [image],
                    platform: platform,
                    outputURL: url
                )
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                onError(error)
            }
        }
    }

    private static func defaultFilename(for image: ImageDescription) -> String {
        let base = image.reference
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "-")
        return "\(base).tar"
    }
}

@MainActor
@Observable
private final class SavePlatformSelection {
    var value: PlatformSelection = .platform(.current)
}

private struct SavePanelAccessoryView: View {
    @Bindable var selection: SavePlatformSelection

    var body: some View {
        HStack(spacing: 12) {
            Text("Platform:")
            Picker("", selection: $selection.value) {
                ForEach(platformOptions, id: \.self) { option in
                    Text(option.description).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(minWidth: 180)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var platformOptions: [PlatformSelection] {
        var options: [PlatformSelection] = [.platform(.current)]

        if Platform.current.architecture == "arm64" {
            options.append(.platform(Platform(arch: "amd64", os: "linux")))
        }

        return options
    }
}
