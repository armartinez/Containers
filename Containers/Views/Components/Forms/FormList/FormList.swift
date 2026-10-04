//
//  FormList.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import SwiftUI

private let cellPadding: CGFloat = 8
private let sectionSpacing: CGFloat = 8

/// A table of items that are either edited in place — pass `rowFields` — or
/// displayed as text and edited in a sheet — pass `editorContent`.
struct FormList<Item: Identifiable, EditorContent: View>: View
where Item.ID: Hashable {

    // MARK: - Properties

    @Environment(\.formListStyle) private var style

    @State var selection = Selection()
    @State private var storedIsExpanded: Bool = true
    @State private var pendingFocusItemID: Item.ID?

    @Binding var items: [Item]

    var title: String?
    var expansion: Binding<Bool>?
    var description: String? = nil
    var editorDescription: String? = nil
    var columnTitles: [String] = ["Value"]
    var addLabel: String
    var emptyMessage: String
    var hasContentBelow: Bool
    var newItem: () -> Item
    var rowFields: ((Binding<Item>) -> [Field])?
    var rowSummary: ((Item) -> String)?
    var rowValues: ((Item) -> [String])?
    var canSave: (Item) -> Bool = { _ in true }

    @ViewBuilder var editorContent: (Binding<Item>) -> EditorContent

    private var usesModalEditor: Bool {
        rowFields == nil
    }

    // Held by the caller when given, so the section survives being rebuilt.
    private var isExpanded: Bool {
        get { expansion?.wrappedValue ?? storedIsExpanded }
        nonmutating set {
            if let expansion {
                expansion.wrappedValue = newValue
            } else {
                storedIsExpanded = newValue
            }
        }
    }

    // MARK: - Types

    /// One editable cell of a row: where its text lives, and what to call it
    /// when it is read aloud. Callers build these, so it cannot be private.
    struct Field: Identifiable {
        let id = UUID()
        var placeholder: String
        var text: Binding<String>
        var isMonospaced: Bool = false
    }

    // MARK: - Initializers

    private init(
        items: Binding<[Item]>,
        title: String?,
        isExpanded: Binding<Bool>?,
        description: String?,
        editorDescription: String?,
        columnTitles: [String],
        addLabel: String,
        emptyMessage: String,
        hasContentBelow: Bool,
        newItem: @escaping () -> Item,
        rowFields: ((Binding<Item>) -> [Field])?,
        rowSummary: ((Item) -> String)?,
        rowValues: ((Item) -> [String])?,
        canSave: @escaping (Item) -> Bool,
        @ViewBuilder editorContent: @escaping (Binding<Item>) -> EditorContent
    ) {
        self._items = items
        self.title = title
        self.expansion = isExpanded
        self.description = description
        self.editorDescription = editorDescription
        self.columnTitles = columnTitles
        self.addLabel = addLabel
        self.emptyMessage = emptyMessage
        self.hasContentBelow = hasContentBelow
        self.newItem = newItem
        self.rowFields = rowFields
        self.rowSummary = rowSummary
        self.rowValues = rowValues
        self.canSave = canSave
        self.editorContent = editorContent
    }

    /// Rows are displayed as text and edited in a sheet built by `editorContent`.
    init(
        items: Binding<[Item]>,
        title: String? = nil,
        isExpanded: Binding<Bool>? = nil,
        description: String? = nil,
        editorDescription: String? = nil,
        columnTitles: [String] = ["Value"],
        addLabel: String,
        emptyMessage: String,
        hasContentBelow: Bool = false,
        newItem: @escaping () -> Item,
        rowSummary: @escaping (Item) -> String,
        rowValues: ((Item) -> [String])? = nil,
        canSave: @escaping (Item) -> Bool = { _ in true },
        @ViewBuilder editorContent: @escaping (Binding<Item>) -> EditorContent
    ) {
        self.init(
            items: items,
            title: title,
            isExpanded: isExpanded,
            description: description,
            editorDescription: editorDescription,
            columnTitles: columnTitles,
            addLabel: addLabel,
            emptyMessage: emptyMessage,
            hasContentBelow: hasContentBelow,
            newItem: newItem,
            rowFields: nil,
            rowSummary: rowSummary,
            rowValues: rowValues,
            canSave: canSave,
            editorContent: editorContent
        )
    }

    // MARK: - Body

    var body: some View {
        content
            .sheet(isPresented: editorPresentation) {
                editor
            }
            .onChange(of: items.endIndex) { _, _ in
                removeStaleSelection()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .table:
            tableContent
        case .grouped:
            groupedContent
        }
    }

    // MARK: - Layout

    private var groupedContent: some View {
        GroupBox {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    if let title {
                        Text(title)
                            .font(.headline)
                            .fontWeight(.bold)
                    }

                    if let description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider()

                rows
                    .frame(minHeight: 80)

                Divider()

                controls(backgroundColor: Color(nsColor: .quaternarySystemFill))
            }
        }
        .groupBoxStyle(BoxStyle())
    }

    private var tableContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                disclosureHeader(title: title)
                    .padding(.vertical, sectionSpacing)
            }

            if isExpanded || title == nil {
                VStack(spacing: 0) {
                    table

                    if title != nil {
                        Divider()
                    }

                    controls()
                        .padding(.leading, title == nil ? 4 : 0)
                }
                .frame(maxHeight: title == nil ? .infinity : nil)
                .padding(.leading, title != nil ? 18 : 0)

                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if (title != nil && !isExpanded) || hasContentBelow {
                Divider()
                    .padding(
                        .top,
                        isExpanded && title != nil ? sectionSpacing : 0
                    )
                    // Last in its container, the rule takes no room: scrolled
                    // to the end it falls just past the clip, and the edge's
                    // own rule is left in its place instead of a point below.
                    .frame(height: hasContentBelow ? nil : 0, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: title == nil ? .infinity : nil, alignment: .leading)
    }

    private func disclosureHeader(title: String) -> some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(
                    systemName: isExpanded ? "chevron.down" : "chevron.right"
                )
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(width: 12)

                Text(title)
                    .font(.headline)

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var table: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(columnTitles.enumerated()), id: \.offset) {
                    index,
                    columnTitle in
                    Text(columnTitle)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .padding(.leading, title == nil ? 12 : 8)
                        .padding(.trailing, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if index < columnTitles.count - 1 {
                        Divider()
                            .padding(.vertical, 4)
                    }
                }
            }
            .frame(height: 22)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            rows
        }
        .background(Color(nsColor: .textBackgroundColor))
        .frame(minHeight: 120)
    }

    @ViewBuilder
    private var rows: some View {
        if items.isEmpty {
            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(items, selection: $selection.selectedItemID) { item in
                selectableRow(for: item.id)
                    .tag(item.id)
                    .contentShape(Rectangle())
            }
            .listStyle(.plain)
        }
    }

    private func controls(backgroundColor: Color? = nil) -> some View {
        Controls(
            addLabel: addLabel,
            isRemoveDisabled: selection.selectedItemID == nil,
            backgroundColor: backgroundColor,
            add: addItem,
            remove: removeSelectedItem
        )
    }

    @ViewBuilder
    private func selectableRow(for id: Item.ID) -> some View {
        if usesModalEditor {
            row(for: id)
                .onTapGesture(count: 2) {
                    openEditor(for: id)
                }
        } else {
            row(for: id)
        }
    }

    @ViewBuilder
    private func row(for id: Item.ID) -> some View {
        if let rowFields, let binding = itemBinding(for: id) {
            FieldRow(
                fields: rowFields(binding),
                isSelected: selection.selectedItemID == id,
                autofocus: pendingFocusItemID == id,
                focusHandled: { pendingFocusItemID = nil }
            )
        } else if let item = items.first(where: { $0.id == id }) {
            Row(values: rowValues(for: item))
        }
    }

    private func rowValues(for item: Item) -> [String] {
        let values = rowValues?(item) ?? rowSummary.map { [$0(item)] } ?? []

        return columnTitles.indices.map { index in
            guard index < values.count else {
                return ""
            }

            return values[index]
        }
    }

    /// An index-based binding outlives the row it was built for: after a removal
    /// SwiftUI can still evaluate the old row, and the index then reads past the
    /// end of the array. Looking the item up by id keeps that harmless, falling
    /// back to the value the row was built with.
    func itemBinding(for id: Item.ID) -> Binding<Item>? {
        guard let current = items.first(where: { $0.id == id }) else {
            return nil
        }

        return Binding(
            get: { items.first { $0.id == id } ?? current },
            set: { updated in
                guard let index = items.firstIndex(where: { $0.id == id })
                else {
                    return
                }

                items[index] = updated
            }
        )
    }

    // MARK: - Actions

    private func addItem() {
        let item = newItem()

        if usesModalEditor {
            selection.editorTarget = .new(item)
        } else {
            selection.append(item, to: &items)
            pendingFocusItemID = item.id
        }
    }

    private func removeSelectedItem() {
        guard let index = selection.selectedIndex(in: items) else {
            return
        }

        selection.remove(at: index, from: &items)
    }

    private func removeStaleSelection() {
        selection.discardStale(in: items)
    }

    // MARK: - Subviews

    /// The add and remove buttons under the rows.
    private struct Controls: View {
        var addLabel: String
        var removeLabel: String = "Remove selected row"
        var isRemoveDisabled: Bool
        var backgroundColor: Color? = nil
        var add: () -> Void
        var remove: () -> Void

        var body: some View {
            HStack(spacing: 0) {
                Button(action: add) {
                    icon("plus")
                }
                .buttonStyle(.plain)
                .help(addLabel)

                Button(action: remove) {
                    icon("minus")
                }
                .buttonStyle(.plain)
                .disabled(isRemoveDisabled)
                .help(removeLabel)

                Spacer()
            }
            .frame(height: 22)
            .background(backgroundColor ?? Color.clear)
        }

        private func icon(_ systemName: String) -> some View {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
    }

    // Strips the default GroupBox padding so the rows meet its edges.
    private struct BoxStyle: GroupBoxStyle {
        func makeBody(configuration: Configuration) -> some View {
            VStack(spacing: 0) {
                configuration.content
            }
            .background(Color(nsColor: .quaternarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    /// Columns of plain text; the values are edited in the editor sheet.
    private struct Row: View {
        var values: [String]

        var body: some View {
            HStack(spacing: 0) {
                ForEach(Array(values.enumerated()), id: \.offset) {
                    index,
                    value in
                    // An item saved with nothing in it would otherwise leave a
                    // blank row with no way to tell it is there.
                    Text(value.isEmpty && index == 0 ? "New Item" : value)
                        // A hierarchical style turns white on the selected row
                        // by itself, in step with the highlight the table draws.
                        .foregroundStyle(value.isEmpty ? .tertiary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, cellPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// Columns of text fields, edited in place.
    private struct FieldRow: View {
        var fields: [Field]
        var isSelected: Bool
        var autofocus: Bool
        var focusHandled: () -> Void

        @FocusState private var focusedFieldIndex: Int?

        var body: some View {
            HStack(spacing: 0) {
                ForEach(Array(fields.enumerated()), id: \.offset) {
                    index,
                    field in
                    // Empty rows stay blank — the column header says what goes
                    // in them — so the field name is left to VoiceOver.
                    TextField("", text: field.text)
                        .textFieldStyle(.plain)
                        .font(font(for: field))
                        .accessibilityLabel(field.placeholder)
                        .focused($focusedFieldIndex, equals: index)
                        .padding(.horizontal, cellPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            // An unselected row's fields would swallow the mouse down in their
            // own tracking loop, leaving the table to select only on mouse up.
            // Letting the click through means the first click selects and the
            // second edits, which is what an AppKit table does anyway.
            .allowsHitTesting(isSelected)
            // Runs both when a freshly inserted row appears and when an existing
            // row is asked to take focus, once the row is in the hierarchy.
            .task(id: autofocus) {
                guard autofocus else { return }

                focusedFieldIndex = 0
                focusHandled()
            }
        }

        private func font(for field: Field) -> Font {
            field.isMonospaced ? .system(.body, design: .monospaced) : .body
        }
    }
}

extension FormList where EditorContent == EmptyView {
    /// Rows are edited in place through the fields `rowFields` describes, so
    /// there is no editor sheet.
    init(
        items: Binding<[Item]>,
        title: String? = nil,
        isExpanded: Binding<Bool>? = nil,
        description: String? = nil,
        columnTitles: [String] = ["Value"],
        addLabel: String,
        emptyMessage: String,
        hasContentBelow: Bool = false,
        newItem: @escaping () -> Item,
        rowFields: @escaping (Binding<Item>) -> [Field]
    ) {
        self.init(
            items: items,
            title: title,
            isExpanded: isExpanded,
            description: description,
            editorDescription: nil,
            columnTitles: columnTitles,
            addLabel: addLabel,
            emptyMessage: emptyMessage,
            hasContentBelow: hasContentBelow,
            newItem: newItem,
            rowFields: rowFields,
            rowSummary: nil,
            rowValues: nil,
            canSave: { _ in true },
            editorContent: { _ in EmptyView() }
        )
    }
}
