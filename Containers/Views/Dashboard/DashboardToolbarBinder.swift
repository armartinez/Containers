//
//  DashboardToolbarBinder.swift
//  Containers
//
//  Created by Axel Martinez on 02/08/2026.
//

import AppKit
import SwiftUI

/// Hands the controller its window, and the current state on every update.
struct DashboardToolbarBinder: NSViewRepresentable {
    let controller: DashboardToolbarController
    let title: String
    let isEnabled: Bool
    let showsFilter: Bool
    let showsAdd: Bool
    let showsClear: Bool
    let isFilterOn: Bool
    let selectionItems: [SelectionToolbarItem]
    let enabledSelectionItems: Set<SelectionToolbarItem>
    let searchText: String
    let searchTokens: [SearchToken]
    let onDeleteSearchTokens: (IndexSet) -> Void
    let onChooseSearchTokenOption: (Int, String) -> Void
    let onSubmitSearch: ((String) -> Void)?
    let onToggleFilter: (Bool) -> Void
    let onAdd: () -> Void
    let onClear: () -> Void
    let onSelectionItem: (SelectionToolbarItem) -> Void
    let onSearch: (String) -> Void
    let addTip: AnyView?
    let runTip: AnyView?
    let accessory: AnyView?

    func makeNSView(context: Context) -> NSView {
        BindingView(controller: controller)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        controller.title = title
        controller.isEnabled = isEnabled
        controller.showsFilter = showsFilter
        controller.showsAdd = showsAdd
        controller.showsClear = showsClear
        controller.isFilterOn = isFilterOn
        controller.selectionItems = selectionItems
        controller.enabledSelectionItems = enabledSelectionItems
        controller.searchText = searchText
        controller.searchTokens = searchTokens
        controller.onDeleteSearchTokens = onDeleteSearchTokens
        controller.onChooseSearchTokenOption = onChooseSearchTokenOption
        controller.onSubmitSearch = onSubmitSearch
        controller.onToggleFilter = onToggleFilter
        controller.onAdd = onAdd
        controller.onClear = onClear
        controller.onSelectionItem = onSelectionItem
        controller.onSearch = onSearch
        controller.addTip = addTip
        controller.runTip = runTip
        controller.accessory = accessory
        controller.update()
    }

    private final class BindingView: NSView {
        let controller: DashboardToolbarController

        init(controller: DashboardToolbarController) {
            self.controller = controller
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) unavailable")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }

            // Deferred: this runs inside the render pass that installing a
            // toolbar would reenter.
            Task { @MainActor in
                controller.attach(to: window)
                controller.update()
            }
        }
    }
}
