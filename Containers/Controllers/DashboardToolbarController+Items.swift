//
//  DashboardToolbarController+Items.swift
//  Containers
//
//  Created by Axel Martinez on 02/08/2026.
//

import AppKit

extension DashboardToolbarController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.identifiers
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.identifiers
    }

    /// Hides unused items on insert, since AppKit can fill the toolbar after the
    /// last update. It fills in order, so the item's index is the current count.
    func toolbarWillAddItem(_ notification: Notification) {
        guard let toolbar = notification.object as? NSToolbar,
            let item = notification.userInfo?["item"] as? NSToolbarItem
        else {
            return
        }

        item.isHidden = !isShown(item.itemIdentifier, at: toolbar.items.count)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case Self.filterIdentifier: filterItem(itemIdentifier)
        case Self.addIdentifier:
            buttonItem(
                itemIdentifier, label: "New", toolTip: "New",
                symbolName: "plus", isEnabled: isEnabled,
                action: #selector(addInvoked))
        case Self.clearIdentifier:
            buttonItem(
                itemIdentifier, label: "Clear",
                toolTip: "Clear all errors",
                symbolName: "xmark.octagon", isEnabled: isEnabled,
                action: #selector(clearInvoked))
        case Self.searchIdentifier: searchItem(itemIdentifier)
        default:
            SelectionToolbarItem(rawValue: itemIdentifier.rawValue)
                .map(selectionItem)
        }
    }

    /// A one-entry group, since only `.selectAny` draws an on state.
    private func filterItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItemGroup {
        let title = "Running containers only"
        let image =
            NSImage(
                systemSymbolName: "line.3.horizontal.decrease",
                accessibilityDescription: title
            ) ?? NSImage()

        let group = NSToolbarItemGroup(
            itemIdentifier: identifier,
            images: [image],
            selectionMode: .selectAny,
            labels: [title],
            target: self,
            action: #selector(filterToggled)
        )
        group.setSelected(isFilterOn, at: 0)
        group.isEnabled = isEnabled
        group.toolTip = title
        return group
    }

    private func selectionItem(_ item: SelectionToolbarItem) -> NSToolbarItem {
        buttonItem(
            NSToolbarItem.Identifier(item.rawValue), label: item.label,
            toolTip: item.toolTip, symbolName: item.symbolName,
            isEnabled: isEnabled && enabledSelectionItems.contains(item),
            action: #selector(selectionItemInvoked))
    }

    private func buttonItem(
        _ identifier: NSToolbarItem.Identifier,
        label: String,
        toolTip: String,
        symbolName: String,
        isEnabled: Bool,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = toolTip
        item.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: label
        )
        item.isBordered = true
        // Enabled from SwiftUI state; AppKit's responder-chain check would always fail.
        item.autovalidates = false
        item.isEnabled = isEnabled
        item.target = self
        item.action = action
        return item
    }

    @objc private func filterToggled(_ sender: NSToolbarItemGroup) {
        onToggleFilter(sender.isSelected(at: 0))
    }

    @objc private func addInvoked(_ sender: NSToolbarItem) {
        onAdd()
    }

    @objc private func clearInvoked(_ sender: NSToolbarItem) {
        onClear()
    }

    @objc private func selectionItemInvoked(_ sender: NSToolbarItem) {
        guard
            let item = SelectionToolbarItem(
                rawValue: sender.itemIdentifier.rawValue
            )
        else { return }

        onSelectionItem(item)
    }
}
