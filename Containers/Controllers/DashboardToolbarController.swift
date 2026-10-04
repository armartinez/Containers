//
//  DashboardToolbarController.swift
//  Containers
//
//  Created by Axel Martinez on 02/08/2026.
//

import AppKit
import SwiftUI

/// Builds the dashboard window's toolbar in AppKit to allow more customization than SwiftUI.
@MainActor
final class DashboardToolbarController: NSObject {
    var isEnabled = true
    var title = ""
    var showsFilter = false
    var showsAdd = true
    var showsClear = false
    var isFilterOn = false
    var selectionItems: [SelectionToolbarItem] = []
    var enabledSelectionItems: Set<SelectionToolbarItem> = []
    var searchText = ""

    var searchTokens: [SearchToken] = []

    /// The section decides what deleting a token means; the field only shows them.
    var onDeleteSearchTokens: (IndexSet) -> Void = { _ in }

    /// The token's index and the chosen option's title.
    var onChooseSearchTokenOption: (Int, String) -> Void = { _, _ in }

    /// `nil` where Return only searches.
    var onSubmitSearch: ((String) -> Void)?

    var onToggleFilter: (Bool) -> Void = { _ in }
    var onAdd: () -> Void = {}
    var onClear: () -> Void = {}
    var onSelectionItem: (SelectionToolbarItem) -> Void = { _ in }
    var onSearch: (String) -> Void = { _ in }
    /// Presented here, since `.popoverTip` can't attach to an AppKit toolbar item.
    var addTip: AnyView?
    var runTip: AnyView?

    /// Shown under the toolbar, in the titlebar.
    var accessory: AnyView?

    static let filterIdentifier = NSToolbarItem.Identifier("filter")
    static let addIdentifier = NSToolbarItem.Identifier("add")
    static let clearIdentifier = NSToolbarItem.Identifier("clear")
    static let searchIdentifier = NSToolbarItem.Identifier("search")

    private weak var window: NSWindow?

    /// Keyed by the anchoring button's label.
    private var tipPopovers: [String: NSPopover] = [:]

    /// Installed once and hidden when unused, so the toolbar isn't laid out again.
    private let accessoryController: NSTitlebarAccessoryViewController = {
        let controller = NSTitlebarAccessoryViewController()
        controller.layoutAttribute = .bottom
        controller.view = NSHostingView(rootView: AnyView(EmptyView()))
        controller.isHidden = true
        return controller
    }()

    func attach(to window: NSWindow) {
        guard self.window !== window else { return }

        self.window = window

        let toolbar = NSToolbar(identifier: "dashboard")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.allowsDisplayModeCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly

        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.addTitlebarAccessoryViewController(accessoryController)

        applyChrome()
    }

    /// Opaque, though transparent would drop the divider: over the content, the
    /// glass goes darker than the search tokens. Reapplied on every update, since
    /// window setup changes it once after the items are installed.
    private func applyChrome() {
        guard let window else { return }

        if window.title != title {
            window.title = title
        }

        if window.titleVisibility != .visible {
            window.titleVisibility = .visible
        }

        if window.titlebarAppearsTransparent {
            window.titlebarAppearsTransparent = false
        }
    }

    /// Every section's items, always installed; each section hides what it doesn't use,
    /// since inserting an item briefly collapses the search field.
    static let identifiers: [NSToolbarItem.Identifier] =
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, filterIdentifier]
        + [SelectionToolbarItem.start, .stop, .run, .details, .delete].map {
            NSToolbarItem.Identifier($0.rawValue)
        }
        // List actions, set apart from the row actions.
        + [.space, clearIdentifier, addIdentifier, .space, searchIdentifier]

    func isShown(_ identifier: NSToolbarItem.Identifier, at index: Int) -> Bool {
        switch identifier {
        case Self.filterIdentifier:
            return showsFilter
        case Self.clearIdentifier:
            return showsClear
        case Self.addIdentifier:
            return showsAdd
        case .space:
            // The first separates row and list actions, so it needs a list action.
            let isBetweenGroups =
                index == Self.identifiers.firstIndex(of: .space)

            return !isBetweenGroups || showsClear || showsAdd
        default:
            guard let item = SelectionToolbarItem(rawValue: identifier.rawValue)
            else {
                return true
            }

            return selectionItems.contains(item)
        }
    }

    func update() {
        guard let toolbar = window?.toolbar else { return }

        applyChrome()

        // Hidden items too, or they'd show stale state when the next section shows them.
        for (index, item) in toolbar.items.enumerated() {
            let isHidden = !isShown(item.itemIdentifier, at: index)

            if item.isHidden != isHidden {
                item.isHidden = isHidden
            }

            switch item.itemIdentifier {
            case Self.filterIdentifier:
                guard let group = item as? NSToolbarItemGroup else { break }
                if group.isSelected(at: 0) != isFilterOn {
                    group.setSelected(isFilterOn, at: 0)
                }
            case Self.searchIdentifier:
                guard let search = item as? NSSearchToolbarItem else { break }

                search.searchField.isEnabled = isEnabled
                show(in: search.searchField)
            default:
                break
            }

            if let selectionItem = SelectionToolbarItem(
                rawValue: item.itemIdentifier.rawValue
            ) {
                item.isEnabled =
                    isEnabled && enabledSelectionItems.contains(selectionItem)
            } else {
                item.isEnabled = isEnabled
            }
        }

        syncTip(addTip, anchoredTo: "New")
        syncTip(runTip, anchoredTo: "Run")
        syncAccessory()
    }

    private func syncAccessory() {
        guard let accessory,
            let hostingView = accessoryController.view as? NSHostingView<AnyView>
        else {
            if !accessoryController.isHidden {
                accessoryController.isHidden = true
            }

            return
        }

        hostingView.rootView = accessory
        hostingView.frame.size.height = hostingView.fittingSize.height

        if accessoryController.isHidden {
            accessoryController.isHidden = false
        }
    }

    private func syncTip(_ tip: AnyView?, anchoredTo label: String) {
        guard let tip else {
            tipPopovers[label]?.close()
            tipPopovers[label] = nil
            return
        }

        guard tipPopovers[label] == nil, let anchor = buttonView(labeled: label)
        else { return }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: tip.frame(width: 260)
        )
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        tipPopovers[label] = popover
    }

    /// Found by accessibility label, since a standard item doesn't expose its `view`.
    private func buttonView(labeled label: String) -> NSView? {
        guard let root = window?.contentView?.superview else { return nil }

        func walk(_ view: NSView) -> NSView? {
            if view.accessibilityRole() == .button,
                view.accessibilityLabel() == label
            {
                return view
            }

            for subview in view.subviews {
                if let found = walk(subview) { return found }
            }

            return nil
        }

        return walk(root)
    }
}
