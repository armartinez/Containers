//
//  SearchField.swift
//  Containers
//
//  Created by Axel Martinez on 25/09/2026.
//

import AppKit

/// A search field that shows the arrow cursor over its tokens instead of the I-beam,
/// both while idle and, through its editor, while typing.
final class SearchField: NSSearchField {
    override class var cellClass: AnyClass? {
        get { SearchFieldCell.self }
        set {}
    }

    /// The token's index and the chosen option's title.
    var onChooseTokenOption: (Int, String) -> Void = { _, _ in }

    func showMenu(
        for token: SearchToken,
        at index: Int,
        below point: NSPoint,
        in view: NSView
    ) {
        guard !token.menu.isEmpty else { return }

        let menu = NSMenu()

        for (group, choices) in token.menu.enumerated() {
            if group > 0 {
                menu.addItem(.separator())
            }

            for choice in choices {
                let item = NSMenuItem(
                    title: choice.title,
                    action: #selector(chooseTokenOption(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = index
                item.state = choice.isOn ? .on : .off

                menu.addItem(item)
            }
        }

        menu.popUp(positioning: nil, at: point, in: view)
    }

    /// Deferred until the click that opened the menu finishes, since the answer
    /// replaces the token that click is still tracking.
    @objc private func chooseTokenOption(_ sender: NSMenuItem) {
        let index = sender.tag
        let title = sender.title

        DispatchQueue.main.async { [onChooseTokenOption] in
            onChooseTokenOption(index, title)
        }
    }

    override var attributedStringValue: NSAttributedString {
        didSet { window?.invalidateCursorRects(for: self) }
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)

        window?.invalidateCursorRects(for: self)
    }

    /// Token and text rects don't overlap, so the cursor never depends on add order.
    override func resetCursorRects() {
        let cells = attributedStringValue.searchTokenCells

        guard isEnabled, !cells.isEmpty,
            let cell = cell as? NSSearchFieldCell
        else {
            super.resetCursorRects()

            return
        }

        let (token, text) = cell.searchTextRect(forBounds: bounds).divided(
            atDistance: cells.map { $0.cellSize().width }.reduce(0, +)
                + TokenFieldEditor.padding,
            from: .minXEdge
        )

        addCursorRect(token, cursor: .arrow)
        addCursorRect(text, cursor: .iBeam)
    }
}

private final class SearchFieldCell: NSSearchFieldCell {
    /// Configured like the window's field editor: one line that scrolls instead of wrapping.
    private let editor: TokenFieldEditor = {
        let editor = TokenFieldEditor(usingTextLayoutManager: false)
        editor.isFieldEditor = true
        editor.isHorizontallyResizable = true
        editor.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        return editor
    }()

    override init(textCell string: String) {
        super.init(textCell: string)

        isScrollable = true
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)

        isScrollable = true
    }

    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        editor
    }
}

/// The field editor, on TextKit 1 so tokens draw inline as attachment cells.
private final class TokenFieldEditor: NSTextView {
    /// Either side of the text, tokens included.
    static let padding: CGFloat = 2

    private var tokenRect: NSRect? {
        guard let count = textStorage?.searchTokenCells.count, count > 0,
            let layoutManager,
            let textContainer
        else {
            return nil
        }

        let glyphs = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: 0, length: count),
            actualCharacterRange: nil
        )
        let rect = layoutManager.boundingRect(
            forGlyphRange: glyphs,
            in: textContainer
        )

        return rect.offsetBy(
            dx: textContainerOrigin.x,
            dy: textContainerOrigin.y
        )
    }

    /// The default, restored when the selection isn't only tokens.
    private lazy var textSelectionAttributes = selectedTextAttributes

    override func resetCursorRects() {
        super.resetCursorRects()

        if let tokenRect {
            addCursorRect(tokenRect, cursor: .arrow)
        }
    }

    /// The selection colour is lighter than a token, so when only tokens are selected
    /// the fill is cleared and each token draws its own darker shade.
    override func setSelectedRanges(
        _ ranges: [NSValue],
        affinity: NSSelectionAffinity,
        stillSelecting: Bool
    ) {
        super.setSelectedRanges(
            ranges,
            affinity: affinity,
            stillSelecting: stillSelecting
        )

        let text = textSelectionAttributes

        selectedTextAttributes =
            holdsTokensOnly(ranges)
            ? [.backgroundColor: NSColor.clear]
            : text
    }

    private func holdsTokensOnly(_ ranges: [NSValue]) -> Bool {
        let text = (textStorage?.string ?? "") as NSString

        guard ranges.contains(where: { $0.rangeValue.length > 0 }) else {
            return false
        }

        return ranges.allSatisfy { value in
            let range = value.rangeValue

            guard NSMaxRange(range) <= text.length else { return false }

            return !text.substring(with: range).contains { $0 != "\u{FFFC}" }
        }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)

        showArrowOverToken(for: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        super.cursorUpdate(with: event)

        showArrowOverToken(for: event)
    }

    override func didChangeText() {
        super.didChangeText()

        window?.invalidateCursorRects(for: self)
    }

    private func showArrowOverToken(for event: NSEvent) {
        guard let tokenRect,
            tokenRect.contains(convert(event.locationInWindow, from: nil))
        else {
            return
        }

        NSCursor.arrow.set()
    }
}
