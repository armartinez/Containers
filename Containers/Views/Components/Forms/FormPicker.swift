//
//  FormPicker.swift
//  Containers
//
//  Created by Axel Martinez on 02/08/2026.
//

import AppKit
import Foundation
import SwiftUI

/// A dropdown that fills the width it is given.
///
/// SwiftUI's menu `Picker` wraps an `NSPopUpButton` but reports its intrinsic
/// width whatever the layout proposes, so it renders visibly narrower than the
/// text fields it shares a column with. Driving the button directly lets
/// `sizeThatFits` accept the proposal instead.
struct FormPicker<Option: Hashable & CustomStringConvertible>: NSViewRepresentable {
    fileprivate enum Item {
        /// The selection when it is none of the options. It titles the button
        /// but stays out of the menu, since it is not something to pick.
        case placeholder(Option, title: String)
        case option(Option, title: String)
        case separator
        /// A trailing command such as "Other…".
        case action(String)
    }

    let placeholder: String
    let options: [Option]

    @Binding var selection: Option

    var fillsAvailableWidth: Bool = true
    var actionTitle: String?
    var onAction: (() -> Void)?
    var title: ((Option) -> String)?
    var icon: ((Option) -> NSImage?)?

    private var items: [Item] {
        var items: [Item] = []

        if !options.contains(selection) {
            items.append(.placeholder(selection, title: placeholder))
        }

        items += options.map { option in
            .option(
                option,
                title: title?(option)
                    ?? (option as? Unit)?.symbol
                    ?? option.description
            )
        }

        if let actionTitle {
            items.append(.separator)
            items.append(.action(actionTitle))
        }

        return items
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.items = items
        context.coordinator.selection = $selection
        context.coordinator.onAction = onAction

        let menu = NSMenu()
        menu.autoenablesItems = false

        for (index, item) in items.enumerated() {
            switch item {
            case .separator:
                menu.addItem(.separator())
            case .option(let option, let title):
                let menuItem = NSMenuItem(
                    title: title,
                    action: nil,
                    keyEquivalent: ""
                )
                menuItem.tag = index
                menuItem.image = icon?(option)
                menu.addItem(menuItem)
            case .placeholder(_, let title):
                let menuItem = NSMenuItem(
                    title: title,
                    action: nil,
                    keyEquivalent: ""
                )
                menuItem.tag = index
                // Hidden rather than absent: the button reads its title from
                // the item it has selected.
                menuItem.isHidden = true
                menu.addItem(menuItem)
            case .action(let title):
                let menuItem = NSMenuItem(
                    title: title,
                    action: nil,
                    keyEquivalent: ""
                )
                menuItem.tag = index
                menu.addItem(menuItem)
            }
        }

        button.menu = menu

        if let index = context.coordinator.index(of: selection) {
            button.selectItem(withTag: index)
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NSPopUpButton,
        context: Context
    ) -> CGSize? {
        let intrinsic = nsView.intrinsicContentSize

        guard fillsAvailableWidth,
            let width = proposal.width,
            width.isFinite
        else {
            return intrinsic
        }

        return CGSize(width: width, height: intrinsic.height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        fileprivate var items: [Item] = []
        var selection: Binding<Option>?
        var onAction: (() -> Void)?

        fileprivate func index(of option: Option) -> Int? {
            items.firstIndex {
                switch $0 {
                case .option(let candidate, _),
                    .placeholder(let candidate, _):
                    return candidate == option
                case .separator, .action:
                    return false
                }
            }
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            guard let tag = sender.selectedItem?.tag,
                items.indices.contains(tag)
            else { return }

            switch items[tag] {
            case .option(let option, _):
                selection?.wrappedValue = option
            case .action:
                if let current = selection?.wrappedValue,
                    let index = index(of: current)
                {
                    sender.selectItem(withTag: index)
                }
                onAction?()
            case .separator, .placeholder:
                break
            }
        }
    }
}
