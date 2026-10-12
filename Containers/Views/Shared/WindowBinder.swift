//
//  WindowBinder.swift
//  Containers
//
//  Created by Axel Martinez on 23/5/26.
//

import AppKit
import SwiftUI

struct WindowBinder: NSViewRepresentable {
    let resizer: WindowResizer

    func makeNSView(context: Context) -> NSView {
        BindingView(resizer: resizer)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    /// Binds on `viewDidMoveToWindow` rather than in `updateNSView`, which can
    /// run before the view has a window and never again after.
    private final class BindingView: NSView {
        let resizer: WindowResizer

        init(resizer: WindowResizer) {
            self.resizer = resizer
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) unavailable")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            MainActor.assumeIsolated { resizer.bind(to: window) }
        }
    }
}
