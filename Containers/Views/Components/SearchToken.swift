//
//  SearchToken.swift
//  Containers
//
//  Created by Axel Martinez on 25/09/2026.
//

import AppKit

struct SearchToken: Equatable, Sendable {
    struct Choice: Equatable, Sendable {
        let title: String
        let isOn: Bool
    }

    /// Drawn small and in capitals before the value.
    let category: String
    let value: String
    /// Offered on double-click, in groups with one choice on in each.
    var menu: [[Choice]] = []
}

/// A token drawn as one character of the search field's text, so it can be clicked,
/// deleted and moved like text while the field stays the native search field.
final class SearchTokenCell: NSTextAttachmentCell {
    let token: SearchToken

    /// Nonisolated, since the layout overrides AppKit calls off the main actor read them.
    nonisolated private enum Style {
        static let cornerRadius: CGFloat = 2
        static let padding: CGFloat = 4.5
        /// From the top of the line to just below its baseline.
        static let height: CGFloat = 16
        static let descent: CGFloat = 3
        /// On either side and below; none above, as the token starts at the top of the line.
        static let margin: CGFloat = 2
        /// Between the category and the value.
        static let separator: CGFloat = 1.5
        static let chevron: CGFloat = 4.5
        static let chevronLeading: CGFloat = 5
        /// Beyond this the value is truncated, so a long name can't fill the field.
        static let maximumValueWidth: CGFloat = 120
    }

    private static let categoryFill = NSColor(name: nil) {
        $0.isDark
            ? NSColor(srgbRed: 0.118, green: 0.118, blue: 0.118, alpha: 1)
            : NSColor(srgbRed: 0.882, green: 0.882, blue: 0.894, alpha: 1)
    }

    private static let valueFill = NSColor(name: nil) {
        $0.isDark
            ? NSColor(srgbRed: 0.055, green: 0.055, blue: 0.055, alpha: 1)
            : NSColor(srgbRed: 0.933, green: 0.933, blue: 0.945, alpha: 1)
    }

    /// Darkens a selected token, since the field's selection colour is lighter than it.
    private static let selectionShade = NSColor(name: nil) {
        $0.isDark
            ? NSColor(white: 0, alpha: 0.45)
            : NSColor(white: 0, alpha: 0.12)
    }

    nonisolated private var categoryFont: NSFont {
        .systemFont(ofSize: 9)
    }

    /// The field's own, so the value matches the typed text.
    nonisolated private var valueFont: NSFont {
        .systemFont(ofSize: NSFont.systemFontSize)
    }

    nonisolated private var categoryText: NSAttributedString {
        NSAttributedString(
            string: token.category.uppercased(),
            attributes: [
                .font: categoryFont,
                .foregroundColor: NSColor.labelColor,
            ]
        )
    }

    nonisolated private var valueText: NSAttributedString {
        let style = NSMutableParagraphStyle()
        // A name's start and end are what tell it apart.
        style.lineBreakMode = .byTruncatingMiddle

        return NSAttributedString(
            string: token.value,
            attributes: [
                .font: valueFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: style,
            ]
        )
    }

    init(token: SearchToken) {
        self.token = token

        super.init()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) unavailable")
    }

    override nonisolated func cellSize() -> NSSize {
        NSSize(
            width: categoryWidth + Style.separator + valueWidth
                + Style.margin * 2,
            height: Style.height + Style.margin
        )
    }

    /// Keeps the value on the text's baseline.
    override nonisolated func cellBaselineOffset() -> NSPoint {
        NSPoint(x: 0, y: -(Style.descent + Style.margin))
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        draw(withFrame: cellFrame, in: controlView, characterIndex: 0)
    }

    override func draw(
        withFrame cellFrame: NSRect,
        in controlView: NSView?,
        characterIndex charIndex: Int
    ) {
        let body = NSRect(
            x: cellFrame.minX + Style.margin,
            y: cellFrame.minY,
            width: cellSize().width - Style.margin * 2,
            height: Style.height
        )
        let baseline = body.maxY - Style.descent

        let category = NSRect(
            x: body.minX,
            y: body.minY,
            width: categoryWidth,
            height: body.height
        )
        let value = NSRect(
            x: category.maxX + Style.separator,
            y: body.minY,
            width: valueWidth,
            height: body.height
        )

        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(
            roundedRect: body,
            xRadius: Style.cornerRadius,
            yRadius: Style.cornerRadius
        ).addClip()

        Self.categoryFill.setFill()
        category.fill()

        Self.valueFill.setFill()
        value.fill()

        if isSelected(at: charIndex, in: controlView) {
            Self.selectionShade.setFill()
            body.fill(using: .sourceOver)
        }

        NSGraphicsContext.current?.restoreGraphicsState()

        categoryText.draw(
            at: NSPoint(
                x: category.minX + Style.padding,
                y: category.midY + categoryFont.capHeight / 2
                    - categoryFont.ascender
            )
        )

        drawChevron(
            in: NSRect(
                x: category.maxX - Style.padding - Style.chevron,
                y: category.midY - Style.chevron / 4,
                width: Style.chevron,
                height: Style.chevron / 2
            )
        )

        // Drawn in a rect, not at a point, so truncation applies.
        valueText.draw(
            in: NSRect(
                x: value.minX + Style.padding,
                y: baseline - valueFont.ascender,
                width: value.width - Style.padding * 2,
                height: valueText.size().height
            )
        )
    }

    /// A click selects the whole token instead of placing the caret; a double-click opens its menu.
    override nonisolated func wantsToTrackMouse() -> Bool {
        true
    }

    override nonisolated func trackMouse(
        with theEvent: NSEvent,
        in cellFrame: NSRect,
        of controlView: NSView?,
        atCharacterIndex charIndex: Int,
        untilMouseUp flag: Bool
    ) -> Bool {
        let clickCount = theEvent.clickCount

        return MainActor.assumeIsolated {
            guard let editor = controlView as? NSTextView else { return false }

            editor.setSelectedRange(
                NSRange(location: charIndex, length: 1)
            )

            if clickCount == 2,
                let field = editor.delegate as AnyObject as? SearchField
            {
                // Tokens lead the text, so the character index is the token index.
                field.showMenu(
                    for: token,
                    at: charIndex,
                    below: NSPoint(x: cellFrame.minX, y: cellFrame.maxY),
                    in: editor
                )
            }

            return true
        }
    }

    private func isSelected(at index: Int, in controlView: NSView?) -> Bool {
        guard let editor = controlView as? NSTextView else { return false }

        return editor.selectedRanges.contains {
            NSLocationInRange(index, $0.rangeValue)
        }
    }

    /// Shows the category can be changed.
    private func drawChevron(in rect: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.midX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        NSColor.labelColor.setStroke()
        path.stroke()
    }

    nonisolated private var categoryWidth: CGFloat {
        categoryText.size().width + Style.padding * 2 + Style.chevron
            + Style.chevronLeading
    }

    nonisolated private var valueWidth: CGFloat {
        min(valueText.size().width, Style.maximumValueWidth) + Style.padding * 2
    }
}

extension NSAppearance {
    fileprivate var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

extension NSAttributedString {
    static func searchField(
        tokens: [SearchToken],
        text: String,
        font: NSFont
    ) -> NSAttributedString {
        let contents = NSMutableAttributedString()

        for token in tokens {
            let attachment = NSTextAttachment()
            attachment.attachmentCell = SearchTokenCell(token: token)

            contents.append(NSAttributedString(attachment: attachment))
        }

        contents.append(NSAttributedString(string: text))

        // Tokens included: text typed after one takes its attributes.
        contents.addAttributes(
            [.font: font, .foregroundColor: NSColor.labelColor],
            range: NSRange(location: 0, length: contents.length)
        )

        return contents
    }

    var searchTokens: [SearchToken] {
        searchTokenCells.map(\.token)
    }

    var searchTokenCells: [SearchTokenCell] {
        var cells: [SearchTokenCell] = []

        enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: length)
        ) { value, _, _ in
            if let cell = (value as? NSTextAttachment)?.attachmentCell
                as? SearchTokenCell
            {
                cells.append(cell)
            }
        }

        return cells
    }

    /// Whether every attachment character comes before the text.
    var hasSearchTokensInFront: Bool {
        !string.drop { $0 == "\u{FFFC}" }.contains("\u{FFFC}")
    }

    var searchFieldText: String {
        string
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}
