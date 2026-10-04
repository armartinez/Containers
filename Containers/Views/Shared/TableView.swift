//
//  TableView.swift
//  Containers
//
//  Created by Axel Martinez on 30/05/2026.
//

import ContainerSystem
import SwiftUI

enum TableStyle {
    case automatic
    case inset
}

/// What a table does with its rows. Each table says only this; showing
/// details, confirming deletes, the toolbar and the context menu are the
/// table's own.
struct TableRowActions<Row> {
    /// What one row is, e.g. "Container".
    var noun: String
    /// What a row is called when asking to delete it.
    var name: (Row) -> String
    var canOpen: (Row) -> Bool = { _ in true }
    var open: (Row) -> Void
    var canDelete: (Row) -> Bool = { _ in true }
    /// Rows with nothing behind them to lose, such as failed work, go
    /// without being asked about.
    var deletesWithoutAsking: (Row) -> Bool = { _ in false }
    var delete: ([Row]) -> Void
    var canStart: ([Row]) -> Bool = { _ in false }
    var start: ([Row]) -> Void = { _ in }
    var canStop: ([Row]) -> Bool = { _ in false }
    var stop: ([Row]) -> Void = { _ in }
    /// The work a row only stands in for, whose own menu it gets instead.
    var pendingWork: (Row) -> ActivitySnapshot? = { _ in nil }
}

struct TableView<Row, Columns, Menu>: View
where
    Row: Identifiable,
    Columns: TableColumnContent<Row, KeyPathComparator<Row>>,
    Menu: View
{
    @Environment(SystemManager.self) private var system
    @Environment(ActivityCenter.self) private var activityCenter
    @Environment(ReportManager.self) private var reportManager

    @Binding var selection: Set<Row.ID>
    @Binding var actions: SelectionActions
    @Binding var command: SelectionCommand?

    let rows: [Row]
    let rowActions: TableRowActions<Row>
    let refreshTrigger: Int
    let tableStyle: TableStyle
    let scrollTo: Row.ID?
    let activityKind: ActivityCenter.Kind?
    let onClear: () -> Void
    let onRefresh: () async throws -> Void
    let menu: ([Row]) -> Menu
    let columns: Columns

    @State private var sortOrder: [KeyPathComparator<Row>]
    @State private var lastUpdated: Date?
    @State private var loadError: ErrorAlert?
    @State private var rowsToDelete: [Row] = []
    @State private var isConfirmingDelete = false

    init(
        rows: [Row],
        selection: Binding<Set<Row.ID>>,
        sortOrder: [KeyPathComparator<Row>],
        actions: Binding<SelectionActions>,
        command: Binding<SelectionCommand?>,
        rowActions: TableRowActions<Row>,
        refreshTrigger: Int,
        tableStyle: TableStyle = .inset,
        scrollTo: Row.ID? = nil,
        activityKind: ActivityCenter.Kind? = nil,
        onClear: @escaping () -> Void,
        onRefresh: @escaping () async throws -> Void,
        @ViewBuilder menu: @escaping ([Row]) -> Menu,
        @TableColumnBuilder<Row, KeyPathComparator<Row>>
        columns: () -> Columns
    ) {
        self.rows = rows
        self._selection = selection
        self._sortOrder = State(initialValue: sortOrder)
        self._actions = actions
        self._command = command
        self.rowActions = rowActions
        self.refreshTrigger = refreshTrigger
        self.tableStyle = tableStyle
        self.scrollTo = scrollTo
        self.activityKind = activityKind
        self.onClear = onClear
        self.onRefresh = onRefresh
        self.menu = menu
        self.columns = columns()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if system.status == .running {
                styledTable
            } else {
                SystemStatusView()
            }
        }
        .onChange(of: system.status, initial: true) {
            guard system.status == .running else {
                onClear()
                lastUpdated = nil
                return
            }

            Task {
                guard lastUpdated == nil else { return }
                await refresh()
            }
        }
        .onChange(of: refreshTrigger) {
            Task { await refresh() }
        }
        .onAppear {
            Task {
                guard system.status == .running else { return }
                await refresh()
            }
        }
        .onChange(of: activityCenter.endings) { _, _ in
            Task {
                await refresh()

                if let activityKind {
                    activityCenter.forgetFinished(ofKind: activityKind)
                }
            }
        }
        .onChange(of: selectionActions, initial: true) { _, newActions in
            actions = newActions
        }
        .onChange(of: command) { _, newCommand in
            guard let newCommand else { return }

            command = nil
            perform(newCommand, on: selection)
        }
        .onDeleteCommand {
            perform(.delete, on: selection)
        }
        .errorAlert($loadError)
        .confirmationDialog(
            rowsToDelete.count > 1
                ? "Delete \(rowsToDelete.count) \(pluralNoun)?"
                : "Delete \(rowActions.noun)?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                rowActions.delete(rowsToDelete)
                rowsToDelete = []
            }

            Button("Cancel", role: .cancel) {
                rowsToDelete = []
            }
        } message: {
            if rowsToDelete.count > 1 {
                Text(
                    "Delete \(rowsToDelete.count) \(pluralNoun.lowercased())? This cannot be undone."
                )
            } else if let row = rowsToDelete.first {
                Text("Delete \(rowActions.name(row))? This cannot be undone.")
            }
        }
    }

    // MARK: - Table

    @ViewBuilder
    private var styledTable: some View {
        switch tableStyle {
        case .automatic:
            table
                .tableStyle(.automatic)
                .background(TableScroller(row: scrollRow))
                .background(TableRowHeight())
        case .inset:
            table
                .tableStyle(.inset)
                .background(TableScroller(row: scrollRow))
                .background(TableRowHeight())
        }
    }

    private var table: some View {
        Table(
            of: Row.self,
            selection: $selection,
            sortOrder: $sortOrder,
            columns: { columns },
            rows: { ForEach(sortedRows) }
        )
        .contextMenu(forSelectionType: Row.ID.self) { ids in
            contextMenu(for: ids)
        } primaryAction: { ids in
            perform(.showDetails, on: ids)
        }
    }

    @ViewBuilder
    private func contextMenu(for ids: Set<Row.ID>) -> some View {
        let selected = rows(for: ids)
        let pendingWork = selected.compactMap(rowActions.pendingWork)

        if !selected.isEmpty, pendingWork.count == selected.count {
            ActivityMenuItems(
                work: pendingWork,
                activityCenter: activityCenter,
                reportManager: reportManager
            )
        } else if !selected.isEmpty {
            Button("Show Details", systemImage: "info.circle") {
                perform(.showDetails, on: ids)
            }
            .disabled(detailsTarget(in: ids) == nil)

            menu(selected)

            Divider()

            Button(
                selected.count > 1
                    ? "Delete \(selected.count) \(pluralNoun)…"
                    : "Delete \(rowActions.noun)…",
                systemImage: "trash",
                role: .destructive
            ) {
                perform(.delete, on: ids)
            }
            .disabled(deletableRows(in: ids).isEmpty)
        }
    }

    // MARK: - Rows

    private var sortedRows: [Row] {
        rows.sorted(using: sortOrder)
    }

    private var pluralNoun: String {
        "\(rowActions.noun)s"
    }

    /// Where the row asked for stands in what the table is showing.
    private var scrollRow: Int? {
        guard let scrollTo else { return nil }

        return sortedRows.firstIndex { $0.id == scrollTo }
    }

    private func rows(for ids: Set<Row.ID>) -> [Row] {
        rows.filter { ids.contains($0.id) }
    }

    /// Details are shown for one row at a time.
    private func detailsTarget(in ids: Set<Row.ID>) -> Row? {
        let selected = rows(for: ids)

        guard selected.count == 1, let row = selected.first,
            rowActions.canOpen(row)
        else { return nil }

        return row
    }

    /// All of the rows, or none where any of them can't be deleted.
    private func deletableRows(in ids: Set<Row.ID>) -> [Row] {
        let selected = rows(for: ids)

        guard selected.allSatisfy(rowActions.canDelete) else { return [] }

        return selected
    }

    // MARK: - Actions

    private var selectionActions: SelectionActions {
        let selected = rows(for: selection)

        return SelectionActions(
            canShowDetails: detailsTarget(in: selection) != nil,
            canStart: rowActions.canStart(selected),
            canStop: rowActions.canStop(selected),
            canDelete: !deletableRows(in: selection).isEmpty
        )
    }

    private func perform(_ command: SelectionCommand, on ids: Set<Row.ID>) {
        let selected = rows(for: ids)

        switch command {
        case .showDetails:
            detailsTarget(in: ids).map(rowActions.open)
        case .start where rowActions.canStart(selected):
            rowActions.start(selected)
        case .stop where rowActions.canStop(selected):
            rowActions.stop(selected)
        case .delete:
            requestDelete(deletableRows(in: ids))
        case .start, .stop:
            break
        }
    }

    private func requestDelete(_ rows: [Row]) {
        let unasked = rows.filter(rowActions.deletesWithoutAsking)

        if !unasked.isEmpty {
            rowActions.delete(unasked)
            selection.subtract(unasked.map(\.id))
        }

        let asked = rows.filter { !rowActions.deletesWithoutAsking($0) }

        guard !asked.isEmpty else { return }

        rowsToDelete = asked
        isConfirmingDelete = true
    }

    private func refresh() async {
        do {
            try await onRefresh()
            lastUpdated = Date()
        } catch {
            loadError = ErrorAlert(
                "The \(pluralNoun.lowercased()) couldn’t be loaded.",
                error: error
            )
        }
    }
}

extension TableView where Menu == EmptyView {
    /// A table with nothing of its own in the context menu, beyond showing
    /// details and deleting.
    init(
        rows: [Row],
        selection: Binding<Set<Row.ID>>,
        sortOrder: [KeyPathComparator<Row>],
        actions: Binding<SelectionActions>,
        command: Binding<SelectionCommand?>,
        rowActions: TableRowActions<Row>,
        refreshTrigger: Int,
        tableStyle: TableStyle = .inset,
        scrollTo: Row.ID? = nil,
        activityKind: ActivityCenter.Kind? = nil,
        onClear: @escaping () -> Void,
        onRefresh: @escaping () async throws -> Void,
        @TableColumnBuilder<Row, KeyPathComparator<Row>>
        columns: () -> Columns
    ) {
        self.init(
            rows: rows,
            selection: selection,
            sortOrder: sortOrder,
            actions: actions,
            command: command,
            rowActions: rowActions,
            refreshTrigger: refreshTrigger,
            tableStyle: tableStyle,
            scrollTo: scrollTo,
            activityKind: activityKind,
            onClear: onClear,
            onRefresh: onRefresh,
            menu: { _ in EmptyView() },
            columns: columns
        )
    }
}

/// What the toolbar can do with the rows selected in a table.
struct SelectionActions: Equatable {
    var canShowDetails = false
    var canStart = false
    var canStop = false
    var canDelete = false
}

/// A toolbar button pressed, for the view that has the rows to act on.
enum SelectionCommand {
    case showDetails
    case start
    case stop
    case delete
}
