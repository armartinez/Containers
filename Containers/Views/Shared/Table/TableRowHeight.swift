//
//  TableRowHeight.swift
//  Containers
//
//  Created by Axel Martinez on 24/09/2026.
//

import AppKit
import SwiftUI

/// Pins the table underneath to its first row's height. With automatic heights,
/// the alternating bands drawn below the last row don't match the rows above.
struct TableRowHeight: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Pinner() }

    func updateNSView(_ nsView: NSView, context: Context) {
        // SwiftUI may lay the table out again on any pass.
        (nsView as? Pinner)?.apply()
    }

    final class Pinner: NSView {
        private var rowHeight: CGFloat?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply(attempt: Int = 0) {
            guard window != nil else { return }

            guard let table = enclosingContentTable, table.numberOfRows > 0
            else {
                // The table appears a few run loop turns later.
                guard attempt < 20 else { return }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    [weak self] in
                    self?.apply(attempt: attempt + 1)
                }

                return
            }

            let height = rowHeight ?? table.rect(ofRow: 0).height

            guard height > 0 else { return }

            rowHeight = height

            if table.usesAutomaticRowHeights {
                table.usesAutomaticRowHeights = false
            }

            if table.rowHeight != height {
                table.rowHeight = height
            }
        }
    }
}
