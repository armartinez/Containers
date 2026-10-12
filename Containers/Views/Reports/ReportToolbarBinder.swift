//
//  ReportToolbarBinder.swift
//  Containers
//
//  Created by Axel Martinez on 16/09/2026.
//

import AppKit
import SwiftUI

/// Hands the controller its window, and what to do with what is searched for.
struct ReportToolbarBinder: NSViewRepresentable {
    let controller: ReportToolbarController
    let onSearch: (String) -> Void

    func makeNSView(context: Context) -> NSView {
        BindingView(controller: controller)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        controller.onSearch = onSearch
    }

    private final class BindingView: NSView {
        let controller: ReportToolbarController

        init(controller: ReportToolbarController) {
            self.controller = controller
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) unavailable")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }

            // Deferred: this runs inside the render pass that installing a
            // toolbar would reenter.
            Task { @MainActor in
                controller.attach(to: window)
            }
        }
    }
}
