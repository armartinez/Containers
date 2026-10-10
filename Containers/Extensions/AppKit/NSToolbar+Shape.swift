//
//  NSToolbar+Shape.swift
//  Containers
//
//  Created by Axel Martinez on 23/09/2026.
//

import AppKit

extension NSToolbar {
    /// Changes only what differs, since emptying and refilling races AppKit's own
    /// filling. Not for toolbars with a search field, which any insert collapses.
    /// - Returns: Whether AppKit had filled the toolbar yet.
    @discardableResult
    func setShape(_ wanted: [NSToolbarItem.Identifier]) -> Bool {
        guard !items.isEmpty else { return false }

        removeSurplus(of: wanted)

        for (index, identifier) in wanted.enumerated() {
            let isInPlace =
                index < items.count && items[index].itemIdentifier == identifier

            if !isInPlace {
                place(identifier, at: index)
            }
        }

        while items.count > wanted.count {
            removeItem(at: items.count - 1)
        }

        return true
    }

    /// Counted, since spacers repeat. The earliest copy goes, so later items keep their place.
    private func removeSurplus(of wanted: [NSToolbarItem.Identifier]) {
        var surplus: [NSToolbarItem.Identifier: Int] = [:]

        for item in items {
            surplus[item.itemIdentifier, default: 0] += 1
        }

        for identifier in wanted {
            surplus[identifier, default: 0] -= 1
        }

        var position = 0

        while position < items.count {
            let identifier = items[position].itemIdentifier

            guard let count = surplus[identifier], count > 0 else {
                position += 1
                continue
            }

            surplus[identifier] = count - 1
            removeItem(at: position)
        }
    }

    /// Moves an existing item, since a toolbar refuses duplicate identifiers.
    private func place(_ identifier: NSToolbarItem.Identifier, at index: Int) {
        guard
            let current = items.firstIndex(where: {
                $0.itemIdentifier == identifier
            })
        else {
            insertItem(withItemIdentifier: identifier, at: index)
            return
        }

        removeItem(at: current)
        insertItem(
            withItemIdentifier: identifier,
            at: current < index ? index - 1 : index
        )
    }
}
