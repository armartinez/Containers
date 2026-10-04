//
//  DetailToolbarBinder.swift
//  Containers
//
//  Created by Axel Martinez on 02/08/2026.
//

import AppKit
import SwiftUI

/// Installs the toolbar as soon as the window exists, before the detail it
/// belongs to has loaded. Declared on the window rather than inside the view
/// that fills it: a toolbar arriving later changes the window's chrome, and
/// so the height everything else is sized against.
struct DetailToolbarAttacher: NSViewRepresentable {
    let controller: DetailToolbarController
    let tabs: [DetailToolbarController.Tab]
    let items: [DetailToolbarItem]

    func makeNSView(context: Context) -> NSView {
        controller.tabs = tabs
        controller.items = items
        return DetailToolbarBinder.BindingView(controller: controller)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Hands the controller its window, and the current state on every update.
struct DetailToolbarBinder: NSViewRepresentable {
    let controller: DetailToolbarController
    let tabs: [DetailToolbarController.Tab]
    let selectedIndex: Int
    let items: [DetailToolbarItem]
    let onSelectTab: (Int) -> Void

    func makeNSView(context: Context) -> NSView {
        BindingView(controller: controller)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        controller.tabs = tabs
        controller.selectedIndex = selectedIndex
        controller.items = items
        controller.onSelectTab = onSelectTab
        controller.update()
    }

    final class BindingView: NSView {
        let controller: DetailToolbarController

        init(controller: DetailToolbarController) {
            self.controller = controller
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) unavailable")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }

            // Before the window is on screen there is no render pass to
            // reenter, and installing here means the toolbar is up before the
            // window is shown rather than arriving a beat after the title bar.
            guard window.isVisible else {
                controller.attach(to: window)
                controller.update()
                return
            }

            // Deferred: this runs inside the render pass that installing a
            // toolbar would reenter.
            Task { @MainActor in
                controller.attach(to: window)
                controller.update()
            }
        }
    }
}
