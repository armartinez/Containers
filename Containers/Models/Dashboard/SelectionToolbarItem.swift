//
//  SelectionToolbarItem.swift
//  Containers
//
//  Created by Axel Martinez on 02/08/2026.
//

/// A toolbar button that acts on the rows selected in the dashboard's table.
enum SelectionToolbarItem: String {
    case details
    case run
    case start
    case stop
    case delete

    var label: String {
        switch self {
        case .details: "Details"
        case .run: "Run"
        case .start: "Start"
        case .stop: "Stop"
        case .delete: "Delete"
        }
    }

    var toolTip: String {
        switch self {
        case .details: "Show details"
        case .run: "Run container from image"
        default: label
        }
    }

    var symbolName: String {
        switch self {
        case .details: "info.circle"
        case .run, .start: "play"
        case .stop: "stop"
        case .delete: "trash"
        }
    }

    var command: SelectionCommand {
        switch self {
        case .run, .start: .start
        case .details: .showDetails
        case .stop: .stop
        case .delete: .delete
        }
    }
}

extension SelectionActions {
    /// The toolbar buttons the selection can use.
    var enabledItems: Set<SelectionToolbarItem> {
        var items: Set<SelectionToolbarItem> = []

        if canStart { items.formUnion([.run, .start]) }
        if canShowDetails { items.insert(.details) }
        if canStop { items.insert(.stop) }
        if canDelete { items.insert(.delete) }

        return items
    }
}
