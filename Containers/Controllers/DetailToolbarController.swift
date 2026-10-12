//
//  DetailToolbarController.swift
//  Containers
//
//  Created by Axel Martinez on 02/08/2026.
//

import AppKit
import SwiftUI

/// Built in AppKit because the tabs need an `NSToolbarItemGroup`: one control with a
/// label per entry. SwiftUI flattens a `ToolbarItemGroup` into separate items.
@MainActor
final class DetailToolbarController: NSObject, NSToolbarDelegate {
    struct Tab: Equatable {
        let title: String
        let icon: String
    }

    var tabs: [Tab] = []
    var selectedIndex = 0
    var items: [DetailToolbarItem] = []
    var onSelectTab: (Int) -> Void = { _ in }

    private static let tabsIdentifier = NSToolbarItem.Identifier("tabs")

    /// Unique per window: AppKit repeats inserts across toolbars sharing an
    /// identifier, which collide with existing items. The display mode is shared
    /// through the defaults instead.
    private let toolbarIdentifier = NSToolbar.Identifier(
        "detail-\(UUID().uuidString)"
    )
    private static let displayModeKey = "detailToolbarDisplayMode"

    private static var savedDisplayMode: NSToolbar.DisplayMode? {
        let raw = UserDefaults.standard.object(forKey: displayModeKey)
        guard let raw = raw as? UInt else { return nil }
        let mode = NSToolbar.DisplayMode(rawValue: raw)
        return mode == .default ? nil : mode
    }

    private weak var window: NSWindow?
    private var displayModeObservation: NSKeyValueObservation?
    private var isRebuildingTabs = false
    private var hasSettled = false
    private var builtShowingLabels: Bool?
    private var builtFrom: [String] = []
    private var appearances: [NSToolbarItem.Identifier: Appearance] = [:]

    func attach(to window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window

        let toolbar = NSToolbar(identifier: toolbarIdentifier)
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = Self.savedDisplayMode ?? .iconOnly
        builtFrom = shape

        window.toolbar = toolbar
        window.toolbarStyle = .unified

        // Labels are usually wider than the icons, so the tabs are rebuilt.
        displayModeObservation = toolbar.observe(
            \.displayMode,
            options: [.initial, .new]
        ) { toolbar, _ in
            MainActor.assumeIsolated {
                UserDefaults.standard.set(
                    toolbar.displayMode.rawValue,
                    forKey: Self.displayModeKey
                )
                self.scheduleTabRebuild()
            }
        }
    }

    /// Returns once the toolbar is installed and done resizing, or on timeout.
    /// It lands a turn after the view, so sizing earlier leaves the window short.
    func whenSettled(timeout: Duration) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)

        while !hasSettled, ContinuousClock.now < deadline {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(8))
        }
    }

    /// Rebuilt because new images don't resize a laid-out item. Deferred and guarded,
    /// since changing items re-reports the display mode, which calls back here.
    private func scheduleTabRebuild() {
        guard !isRebuildingTabs, builtShowingLabels != showsLabels else {
            if !isRebuildingTabs { hasSettled = true }
            return
        }

        isRebuildingTabs = true

        Task { @MainActor in
            rebuildTabs()
            isRebuildingTabs = false

            // The mode can change again while a rebuild is pending.
            scheduleTabRebuild()
        }
    }

    private func rebuildTabs() {
        builtShowingLabels = showsLabels

        guard
            let toolbar = window?.toolbar,
            let index = toolbar.items.firstIndex(where: {
                $0.itemIdentifier == Self.tabsIdentifier
            })
        else { return }

        toolbar.removeItem(at: index)
        toolbar.insertItem(withItemIdentifier: Self.tabsIdentifier, at: index)
    }

    private var showsLabels: Bool {
        switch window?.toolbar?.displayMode {
        case .iconAndLabel, .labelOnly: true
        default: false
        }
    }

    /// A tab is only as wide as its image, so the image is padded to fit the label.
    private var tabImages: [NSImage] {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        return tabs.map { tab in
            let image =
                NSImage(
                    systemSymbolName: tab.icon,
                    accessibilityDescription: tab.title
                ) ?? NSImage()

            guard showsLabels else { return image }

            let caption = tab.title as NSString
            let width = caption.size(withAttributes: [.font: font]).width
            // The caption alone; the toolbar adds its own padding.
            return image.widened(to: ceil(width))
        }
    }

    func update() {
        guard let toolbar = window?.toolbar else { return }

        guard builtFrom == shape else {
            if rebuild(toolbar) {
                builtFrom = shape
            }

            return
        }

        for item in toolbar.items {
            if let group = item as? NSToolbarItemGroup {
                if group.selectedIndex != selectedIndex {
                    group.selectedIndex = selectedIndex
                }
            } else if let detailItem = detailItem(for: item.itemIdentifier) {
                // Run becoming Stop, or a report badge appearing, changes the item in place.
                apply(detailItem, to: item)
            }
        }
    }

    /// Changes here rebuild the toolbar; other state is applied in place.
    private var shape: [String] {
        leadingItems.map(\.id) + tabs.map(\.title) + ["·"]
            + trailingItems.map(\.id)
    }

    private var leadingItems: [DetailToolbarItem] {
        items.filter(\.isLeading)
    }

    private var trailingItems: [DetailToolbarItem] {
        items.filter { !$0.isLeading }
    }

    /// Unanimated, so items don't fade in after the opening window's title.
    private func rebuild(_ toolbar: NSToolbar) -> Bool {
        var shaped = false

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0

            shaped = toolbar.setShape(identifiers)
        }

        return shaped
    }

    private var identifiers: [NSToolbarItem.Identifier] {
        var result: [NSToolbarItem.Identifier] = []

        result += leadingItems.map { NSToolbarItem.Identifier($0.id) }

        if !tabs.isEmpty {
            // Leaves room for a badge drawn past the last leading item's edge.
            if !leadingItems.isEmpty {
                result.append(.space)
            }

            result.append(Self.tabsIdentifier)
            result.append(.flexibleSpace)
        }

        result += trailingItems.map { NSToolbarItem.Identifier($0.id) }

        return result
    }

    private func detailItem(for identifier: NSToolbarItem.Identifier) -> DetailToolbarItem? {
        items.first { $0.id == identifier.rawValue }
    }

    /// Only changes are written, since new images trigger a toolbar layout.
    private struct Appearance: Equatable {
        let title: String
        let help: String
        let icon: String
        let isHidden: Bool

        init(_ detailItem: DetailToolbarItem) {
            self.title = detailItem.title
            self.help = detailItem.help
            self.icon = detailItem.icon
            self.isHidden = detailItem.isHidden
        }
    }

    private func apply(_ detailItem: DetailToolbarItem, to item: NSToolbarItem) {
        item.isEnabled = detailItem.isEnabled

        let appearance = Appearance(detailItem)

        guard appearances[item.itemIdentifier] != appearance else { return }

        appearances[item.itemIdentifier] = appearance

        item.label = detailItem.title
        item.paletteLabel = detailItem.title
        item.toolTip = detailItem.help
        item.isHidden = detailItem.isHidden

        item.image = image(for: detailItem)
    }

    /// A system symbol, or else a badged one from the asset catalog.
    ///
    /// Badged symbols draw their badge, the primary layer, in red and the rest
    /// in the label color. Multicolor would draw the rest too dark in Dark Mode.
    private func image(for detailItem: DetailToolbarItem) -> NSImage? {
        if let symbol = NSImage(systemSymbolName: detailItem.icon, accessibilityDescription: detailItem.title) {
            return symbol
        }

        let symbol = NSImage(named: detailItem.icon)
        symbol?.accessibilityDescription = detailItem.title
        return symbol?.withSymbolConfiguration(.init(paletteColors: [.systemRed, .labelColor]))
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
        if itemIdentifier == Self.tabsIdentifier {
            return tabGroup(itemIdentifier)
        }

        guard let detailItem = detailItem(for: itemIdentifier) else { return nil }
        return buttonItem(itemIdentifier, for: detailItem)
    }

    private func tabGroup(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItemGroup {
        let group = NSToolbarItemGroup(
            itemIdentifier: identifier,
            images: tabImages,
            selectionMode: .selectOne,
            labels: tabs.map(\.title),
            target: self,
            action: #selector(tabSelected)
        )
        group.selectedIndex = selectedIndex
        group.visibilityPriority = .high
        group.controlRepresentation = .expanded
        return group
    }

    private func buttonItem(
        _ identifier: NSToolbarItem.Identifier,
        for detailItem: DetailToolbarItem
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.isBordered = true
        item.autovalidates = false
        item.target = self
        item.action = #selector(itemInvoked)

        appearances[identifier] = nil
        apply(detailItem, to: item)

        return item
    }

    @objc private func tabSelected(_ sender: NSToolbarItemGroup) {
        onSelectTab(sender.selectedIndex)
    }

    @objc private func itemInvoked(_ sender: NSToolbarItem) {
        detailItem(for: sender.itemIdentifier)?.action()
    }
}

extension NSImage {
    fileprivate func widened(to width: CGFloat) -> NSImage {
        guard width > size.width else { return self }

        let padded = NSImage(
            size: NSSize(width: width, height: size.height),
            flipped: false
        ) { [self] bounds in
            draw(
                at: NSPoint(x: (bounds.width - size.width) / 2, y: 0),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            return true
        }

        padded.isTemplate = isTemplate
        return padded
    }
}
