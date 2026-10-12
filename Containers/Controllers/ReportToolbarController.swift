//
//  ReportToolbarController.swift
//  Containers
//
//  Created by Axel Martinez on 16/09/2026.
//

import AppKit
import SwiftUI

/// Built in AppKit because SwiftUI's search field takes all the leftover width.
final class ReportToolbarController: NSObject, NSToolbarDelegate {
    var onSearch: (String) -> Void = { _ in }

    private static let searchIdentifier = NSToolbarItem.Identifier("search")

    private weak var window: NSWindow?

    func attach(to window: NSWindow) {
        guard self.window !== window else { return }

        self.window = window

        let toolbar = NSToolbar(identifier: "report")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.allowsDisplayModeCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly

        window.toolbar = toolbar
        window.toolbarStyle = .unified
    }

    private var identifiers: [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.searchIdentifier]
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        identifiers
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        identifiers
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == Self.searchIdentifier else { return nil }

        return searchItem(itemIdentifier)
    }

    /// The preferred width is only a minimum, so the maximum is capped too.
    private func searchItem(
        _ identifier: NSToolbarItem.Identifier
    ) -> NSSearchToolbarItem {
        let item = NSSearchToolbarItem(itemIdentifier: identifier)
        item.searchField.placeholderString = "Search"
        item.searchField.delegate = self
        item.preferredWidthForSearchField = 192
        item.searchField.widthAnchor
            .constraint(lessThanOrEqualToConstant: 192).isActive = true
        item.resignsFirstResponderWithCancel = true
        return item
    }
}

extension ReportToolbarController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else { return }

        onSearch(field.stringValue)
    }
}
