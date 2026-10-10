//
//  TableScroller.swift
//  Containers
//
//  Created by Axel Martinez on 16/09/2026.
//

import AppKit
import SwiftUI

/// Brings a row of a table into view.
///
/// SwiftUI cannot do this to a `Table` on macOS: neither `scrollPosition(id:)`
/// nor a `ScrollPosition` binding moves one, so the table AppKit draws
/// underneath is asked directly. Sitting behind the table is what finds it.
struct TableScroller: NSViewRepresentable {
    let row: Int?

    func makeNSView(context: Context) -> NSView {
        Scroller()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? Scroller)?.row = row
    }

    final class Scroller: NSView {
        var row: Int? {
            didSet {
                guard row != oldValue else { return }

                scroll()
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scroll()
        }

        /// The table is not there the moment a row is asked for, so it is
        /// given a few turns of the run loop to appear.
        private func scroll(attempt: Int = 0) {
            guard let row else { return }

            guard let table = enclosingContentTable else {
                guard attempt < 10 else { return }

                DispatchQueue.main.async { [weak self] in
                    self?.scroll(attempt: attempt + 1)
                }

                return
            }

            guard row >= 0, row < table.numberOfRows else { return }

            table.scrollRowToVisible(row)
        }
    }
}
