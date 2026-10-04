//
//  NSView+ContentTable.swift
//  Containers
//
//  Created by Axel Martinez on 24/09/2026.
//

import AppKit

extension NSView {
    /// The `NSTableView` behind a SwiftUI `Table`, found by walking up from this
    /// view, since SwiftUI doesn't expose it. Skips the sidebar's source list.
    var enclosingContentTable: NSTableView? {
        var ancestor = superview

        while let current = ancestor {
            let found = Self.tables(in: current).first {
                $0.style != .sourceList
            }

            if let found { return found }

            ancestor = current.superview
        }

        return nil
    }

    private static func tables(in view: NSView) -> [NSTableView] {
        if let table = view as? NSTableView { return [table] }

        return view.subviews.flatMap(tables)
    }
}
