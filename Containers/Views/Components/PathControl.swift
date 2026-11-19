//
//  PathControl.swift
//  Containers
//
//  Created by Axel Martinez on 2026/11/16.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A file or folder shown as the folders that lead to it, in an `NSPathControl`.
///
/// In the standard style it shows the path, as Music shows its media folder, and a click on a folder opens it in
/// Finder. In the pop-up style its menu lists the folders that lead to it, and "Choose…" picks another in an open
/// panel. When it chooses a folder, one of the folders above can be picked too; the sandbox only grants access to what
/// the panel returns, so the panel confirms the pick unless the app can already read that folder.
struct PathControl: NSViewRepresentable {
    @Binding var url: URL?
    var style: NSPathControl.Style = .standard
    var placeholder = ""
    var allowedContentTypes: [UTType] = []
    var choosesDirectories = false
    var defaultDirectory: URL?
    var onSelection: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSPathControl {
        let pathControl = NSPathControl()
        pathControl.pathStyle = style
        pathControl.isEditable = style == .popUp
        pathControl.focusRingType = .none
        pathControl.delegate = context.coordinator
        pathControl.target = context.coordinator
        pathControl.action = #selector(Coordinator.pathChanged(_:))
        pathControl.setContentHuggingPriority(.defaultLow, for: .horizontal)
        pathControl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return pathControl
    }

    func updateNSView(_ pathControl: NSPathControl, context: Context) {
        context.coordinator.parent = self

        if pathControl.url != url {
            pathControl.url = url
        }

        pathControl.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: NSColor.placeholderTextColor]
        )
        pathControl.isEnabled = context.environment.isEnabled
    }

    @MainActor
    final class Coordinator: NSObject, NSPathControlDelegate {
        var parent: PathControl
        private var isChoosing = false

        init(parent: PathControl) {
            self.parent = parent
        }

        @objc func pathChanged(_ pathControl: NSPathControl) {
            // As in Music, a click on a folder of the path opens it in Finder.
            if pathControl.pathStyle == .standard, let clicked = pathControl.clickedPathItem?.url {
                if !NSWorkspace.shared.open(clicked) {
                    NSWorkspace.shared.activateFileViewerSelecting([clicked])
                }
            }

            guard isChoosing else {
                let picked = pathControl.clickedPathItem?.url
                pathControl.url = parent.url

                if pathControl.pathStyle == .popUp, parent.choosesDirectories, let picked, picked != parent.url {
                    choose(picked)
                }

                return
            }

            isChoosing = false
            select(pathControl.url)
        }

        func pathControl(_ pathControl: NSPathControl, willPopUp menu: NSMenu) {
            isChoosing = false
            menu.autoenablesItems = false

            // The folders carry icons; "Choose…" doesn't. A folder can be swapped for one above it, a file can't.
            for item in menu.items where item.image != nil {
                item.isEnabled = parent.choosesDirectories
            }
        }

        func pathControl(_ pathControl: NSPathControl, willDisplay openPanel: NSOpenPanel) {
            isChoosing = true
            configure(openPanel, startingAt: parent.url?.deletingLastPathComponent() ?? parent.defaultDirectory)
        }

        /// A folder above the current one is used as it is when the app can already read it, and otherwise confirmed
        /// in the open panel, which is what grants the sandbox access to it.
        private func choose(_ folder: URL) {
            if (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) != nil {
                select(folder)
                return
            }

            let panel = NSOpenPanel()
            configure(panel, startingAt: folder)

            Task {
                guard let url = await panel.presentAsSheet() else { return }

                select(url)
            }
        }

        private func select(_ url: URL?) {
            parent.url = url
            parent.onSelection?()
        }

        private func configure(_ openPanel: NSOpenPanel, startingAt directory: URL?) {
            openPanel.allowsMultipleSelection = false
            openPanel.canChooseFiles = !parent.choosesDirectories
            openPanel.canChooseDirectories = parent.choosesDirectories
            openPanel.canCreateDirectories = parent.choosesDirectories
            openPanel.showsHiddenFiles = true
            openPanel.directoryURL = directory

            if !parent.allowedContentTypes.isEmpty {
                openPanel.allowedContentTypes = parent.allowedContentTypes
            }
        }
    }
}

#Preview {
    @Previewable @State var dockerfile: URL? = FileSelection.userHomeDirectory.appending(path: "Documents/web/Dockerfile")
    @Previewable @State var buildDirectory: URL?

    VStack(alignment: .leading, spacing: 12) {
        PathControl(url: .constant(UserDefaults.defaultAppRoot))
        PathControl(url: $dockerfile, style: .popUp, placeholder: "None")
        PathControl(url: $buildDirectory, style: .popUp, placeholder: "None", choosesDirectories: true)
    }
    .padding(24)
    .frame(width: 520)
}
