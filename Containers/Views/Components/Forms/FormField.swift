//
//  FormField.swift
//  Containers
//
//  Created by Axel Martinez on 30/05/2026.
//

import AppKit
import SwiftUI

/// A text field in a form. The placeholder is a prompt rather than a title, so
/// the enclosing `Form` does not promote it to the row's label.
struct FormField: View {
    /// The gap the button sits in, wide enough for a template image and the
    /// margin the bezel already keeps on that side.
    private static let actionWidth: CGFloat = 20

    let placeholder: String

    @Binding var value: String

    var isEditable: Bool = true
    var filter: ((String) -> String)?
    var actionIcon: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        field
            .overlay(alignment: .trailing) {
                if let actionIcon, let actionTitle, let action {
                    Button(action: action) {
                        Label(actionTitle, systemImage: actionIcon)
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help(actionTitle)
                    .padding(.trailing, 5)
                }
            }
    }

    /// A filtered field has to correct the text being edited, which only the
    /// AppKit one can do: writing a rejected keystroke back through a binding
    /// leaves the value it started at, so SwiftUI never redraws and the field
    /// goes on showing what was refused.
    @ViewBuilder
    private var field: some View {
        if action == nil, filter == nil {
            TextField(text: $value, prompt: Text(placeholder)) {
                EmptyView()
            }
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .disabled(!isEditable)
        } else {
            InsetField(
                value: $value,
                placeholder: placeholder,
                isEditable: isEditable,
                filter: filter,
                trailingInset: action == nil ? 0 : Self.actionWidth
            )
        }
    }
}

/// A field that keeps its trailing edge clear, so a button can sit inside the
/// bezel without the value running underneath it.
///
/// SwiftUI has no way to inset a text field's text, and an overlaid button only
/// covers it. `NSTextFieldCell` draws where it is told, which leaves the bezel
/// and its focus ring the system's own.
private struct InsetField: NSViewRepresentable {
    @Binding var value: String
    let placeholder: String
    let isEditable: Bool
    let filter: ((String) -> String)?
    let trailingInset: CGFloat

    func makeNSView(context: Context) -> NSTextField {
        let cell = InsetCell(textCell: "")
        cell.isBezeled = true
        cell.bezelStyle = .roundedBezel
        cell.isEditable = true
        cell.isSelectable = true
        cell.isScrollable = true
        cell.usesSingleLineMode = true
        cell.lineBreakMode = .byTruncatingTail

        let field = NSTextField()
        field.cell = cell
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.value = $value
        context.coordinator.filter = filter

        let cell = field.cell as? InsetCell
        cell?.trailingInset = trailingInset
        cell?.lineBreakMode = context.environment.isEnabled ? .byClipping : .byTruncatingTail
        field.placeholderString = placeholder
        field.isEnabled = context.environment.isEnabled
        field.isEditable = isEditable && context.environment.isEnabled
        field.isSelectable = true

        if field.stringValue != value {
            field.stringValue = value
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NSTextField,
        context: Context
    ) -> CGSize? {
        let intrinsic = nsView.intrinsicContentSize

        guard let width = proposal.width, width.isFinite else {
            return intrinsic
        }

        return CGSize(width: width, height: intrinsic.height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var value: Binding<String>?
        var filter: ((String) -> String)?

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else {
                return
            }

            if let filter {
                let filtered = filter(field.stringValue)

                if filtered != field.stringValue {
                    NSSound.beep()
                    replace(field.stringValue, with: filtered, in: field)
                }
            }

            value?.wrappedValue = field.stringValue
        }

        /// Puts the accepted text back into the field being edited, keeping the
        /// insertion point where the typing left it rather than at the end.
        private func replace(
            _ text: String,
            with filtered: String,
            in field: NSTextField
        ) {
            let editor = field.currentEditor()
            let caret = editor?.selectedRange.location ?? 0
            let dropped = text.count - filtered.count

            field.stringValue = filtered

            editor?.selectedRange = NSRange(
                location: min(max(0, caret - dropped), filtered.count),
                length: 0
            )
        }
    }

    private final class InsetCell: NSTextFieldCell {
        var trailingInset: CGFloat = 0

        override func drawingRect(forBounds rect: NSRect) -> NSRect {
            var rect = super.drawingRect(forBounds: rect)
            rect.size.width = max(0, rect.width - trailingInset)
            return rect
        }
    }
}
