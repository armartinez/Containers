//
//  DashboardToolbarController+Search.swift
//  Containers
//
//  Created by Axel Martinez on 02/08/2026.
//

import AppKit

extension DashboardToolbarController {
    func searchItem(_ identifier: NSToolbarItem.Identifier) -> NSSearchToolbarItem {
        let item = NSSearchToolbarItem(itemIdentifier: identifier)
        let field = SearchField()
        item.searchField = field

        field.onChooseTokenOption = { [weak self] index, title in
            self?.onChooseSearchTokenOption(index, title)
        }

        field.placeholderString = "Search"
        field.delegate = self
        // Tokens are attachments, so the field must accept attributed text.
        field.allowsEditingTextAttributes = true
        field.isEnabled = isEnabled

        // The preferred width is only a minimum, so the maximum is capped too.
        item.preferredWidthForSearchField = 176
        field.widthAnchor.constraint(lessThanOrEqualToConstant: 260).isActive = true
        item.resignsFirstResponderWithCancel = true
        item.isEnabled = isEnabled

        show(in: field)

        return item
    }

    /// Writes to the editor while typing, since setting the field's value would end
    /// editing and lose the caret.
    func show(in field: NSSearchField) {
        let contents = Self.contents(of: field)

        guard
            contents.searchTokens != searchTokens
                || contents.searchFieldText != searchText
        else {
            return
        }

        let wanted = NSAttributedString.searchField(
            tokens: searchTokens,
            text: searchText,
            font: field.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        )

        guard let editor = field.currentEditor() as? NSTextView else {
            field.attributedStringValue = wanted

            return
        }

        editor.textStorage?.setAttributedString(wanted)
        editor.setSelectedRange(
            NSRange(location: wanted.length, length: 0)
        )
    }

    /// Read from the editor while typing, since the field's value lags until editing ends.
    static func contents(of field: NSSearchField) -> NSAttributedString {
        guard let editor = field.currentEditor() as? NSTextView,
            let storage = editor.textStorage
        else {
            return field.attributedStringValue
        }

        return NSAttributedString(attributedString: storage)
    }
}

extension DashboardToolbarController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else { return }

        let contents = Self.contents(of: field)

        // Removed here too, so reordering the rest doesn't restore it.
        let deleted = deletedTokens(keeping: contents.searchTokens)

        if !deleted.isEmpty {
            searchTokens = searchTokens.enumerated()
                .filter { !deleted.contains($0.offset) }
                .map(\.element)

            onDeleteSearchTokens(deleted)
        }

        // Tokens always go first, even if text is typed in front of them.
        if !contents.hasSearchTokensInFront {
            searchText = contents.searchFieldText
            show(in: field)
            onSearch(searchText)

            return
        }

        searchText = contents.searchFieldText
        onSearch(searchText)
    }

    /// Return turns the text into a token where the section supports it, as in Console.
    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        let text = searchText.trimmingCharacters(in: .whitespaces)

        guard commandSelector == #selector(NSResponder.insertNewline(_:)),
            let onSubmitSearch, !text.isEmpty
        else {
            return false
        }

        onSubmitSearch(text)

        return true
    }

    /// Indices of tokens no longer in the field; the rest keep their order.
    private func deletedTokens(keeping kept: [SearchToken]) -> IndexSet {
        var kept = kept[...]
        var deleted = IndexSet()

        for (index, token) in searchTokens.enumerated() {
            if kept.first == token {
                kept.removeFirst()
            } else {
                deleted.insert(index)
            }
        }

        return deleted
    }
}
