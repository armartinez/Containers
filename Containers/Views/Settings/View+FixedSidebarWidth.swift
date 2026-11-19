//
//  View+FixedSidebarWidth.swift
//  Containers
//
//  Created by Axel Martinez on 2026/11/15.
//

import AppKit
import SwiftUI

extension View {
    /// Keeps the sidebar of a `NavigationSplitView` at a fixed width, which SwiftUI otherwise lets the user drag, or drag closed.
    func fixedSidebarWidth(_ width: CGFloat) -> some View {
        background(FixedSidebarWidth(width: width))
    }
}

private struct FixedSidebarWidth: NSViewRepresentable {
    let width: CGFloat

    func makeNSView(context: Context) -> SidebarWidthView {
        SidebarWidthView(width: width)
    }

    func updateNSView(_ nsView: SidebarWidthView, context: Context) {}

    final class SidebarWidthView: NSView {
        private let width: CGFloat
        private var observations: [NSKeyValueObservation] = []

        init(width: CGFloat) {
            self.width = width
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            observations = []

            guard window != nil else { return }

            // SwiftUI adds the split view after this view joins the window.
            Task { @MainActor [weak self] in
                self?.observeSidebar()
            }
        }

        /// SwiftUI only takes an ideal width for the sidebar, and clears its limits whenever it updates the split view,
        /// so they're set again the moment it does.
        private func observeSidebar() {
            guard let sidebar = enclosingSidebarItem else { return }

            applyFixedWidth()

            // SwiftUI changes the limits on the main thread.
            let reapply: @Sendable () -> Void = { [weak self] in
                MainActor.assumeIsolated {
                    self?.applyFixedWidth()
                }
            }

            observations = [
                sidebar.observe(\.minimumThickness) { _, _ in reapply() },
                sidebar.observe(\.maximumThickness) { _, _ in reapply() },
                sidebar.observe(\.canCollapse) { _, _ in reapply() },
            ]
        }

        private func applyFixedWidth() {
            guard let sidebar = enclosingSidebarItem else { return }

            if sidebar.canCollapse {
                sidebar.canCollapse = false
            }

            if sidebar.minimumThickness != width {
                sidebar.minimumThickness = width
            }

            if sidebar.maximumThickness != width {
                sidebar.maximumThickness = width
            }
        }

        private var enclosingSidebarItem: NSSplitViewItem? {
            var ancestor = superview

            while let current = ancestor {
                if let splitView = current as? NSSplitView, let controller = splitView.delegate as? NSSplitViewController {
                    return controller.splitViewItems.first
                }

                ancestor = current.superview
            }

            return nil
        }
    }
}
