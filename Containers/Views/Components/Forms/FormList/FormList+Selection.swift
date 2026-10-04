//
//  FormList+Selection.swift
//  Containers
//
//  Created by Axel Martinez on 2026/08/09.
//

import SwiftUI

// MARK: - Selection

extension FormList {
    /// Which item is selected, which one is being edited, and where both
    /// land when an item is added or removed. The items themselves stay in
    /// the caller's binding.
    struct Selection {
        /// A new item is carried here rather than looked up, because some lists
        /// only append it once the editor is saved.
        enum EditorTarget {
            case existing(Item.ID)
            case new(Item)
        }

        var selectedItemID: Item.ID?
        var editorTarget: EditorTarget?

        nonisolated init() {}

        var isEditingNewItem: Bool {
            if case .new = editorTarget {
                return true
            }

            return false
        }

        func selectedIndex(in items: [Item]) -> [Item].Index? {
            guard let selectedItemID else {
                return nil
            }

            return items.firstIndex { $0.id == selectedItemID }
        }

        mutating func select(_ id: Item.ID?) {
            selectedItemID = id
        }

        mutating func edit(_ id: Item.ID) {
            selectedItemID = id
            editorTarget = .existing(id)
        }

        mutating func closeEditor() {
            editorTarget = nil
        }

        mutating func append(_ item: Item, to items: inout [Item]) {
            items.append(item)
            selectedItemID = item.id
        }

        mutating func remove(at index: [Item].Index, from items: inout [Item]) {
            let removedID = items[index].id
            items.remove(at: index)

            if items.isEmpty {
                selectedItemID = nil
            } else {
                // The row that moved up into the gap inherits the selection.
                selectedItemID = items[min(index, items.endIndex - 1)].id
            }

            if case .existing(removedID) = editorTarget {
                closeEditor()
            }
        }

        /// Drops a selection or an editor left pointing at an item that no longer
        /// exists, and closes the editor once a new item has been appended.
        mutating func discardStale(in items: [Item]) {
            if let selectedItemID,
                !items.contains(where: { $0.id == selectedItemID })
            {
                self.selectedItemID = nil
            }

            switch editorTarget {
            case .existing(let id) where !items.contains(where: { $0.id == id }):
                closeEditor()
            case .new(let item) where items.contains(where: { $0.id == item.id }):
                closeEditor()
            case .existing, .new, nil:
                break
            }
        }
    }
}
