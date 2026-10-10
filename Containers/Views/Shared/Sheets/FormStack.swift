//
//  FormStack.swift
//  Containers
//
//  Created by Axel Martinez on 09/08/2026.
//

import SwiftUI

/// A sheet's form, centred on what it draws.
///
/// `Form` sizes the label column to the widest label and lines the controls up
/// under it. Sizing the stack to that and then filling the width is what
/// centres the result rather than leaving it against the leading edge.
///
/// The header sits outside the form so it can span both columns; a row inside
/// one only ever occupies the control column.
struct FormStack<Header: View, Content: View>: View {
    /// Where the fields begin, as a share of the width the sheet gives the
    /// form, and how much of that the labels before them take. Proportions
    /// rather than measures keep every tab's fields in one place, whatever a
    /// tab happens to call its rows.
    ///
    /// The labels take the larger share of the two: the longest of them has
    /// to read on one line, and the room comes out of the margin before them
    /// rather than out of where the fields start.
    private static var fieldStartRatio: CGFloat { 1 / 3 }
    private static var labelWidthRatio: CGFloat { 1 / 5 }

    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    @State private var availableWidth: CGFloat = .zero

    /// What stands before the label column, so the fields start where they
    /// should.
    private var formLeading: CGFloat {
        max(
            0,
            availableWidth * Self.fieldStartRatio
                - availableWidth * Self.labelWidthRatio
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
                .frame(idealWidth: 0, maxWidth: .infinity)

            Form {
                content
            }
            .formStyle(.columns)
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.leading, formLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Measured after the fill, so it is the room the sheet gives the form
        // rather than the room the form asked for.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            availableWidth = width
        }
        .environment(\.formLabelWidth, availableWidth * Self.labelWidthRatio)
        .environment(\.formProseWidth, availableWidth * (1 - Self.fieldStartRatio))
    }
}

extension EnvironmentValues {
    /// The width every row gives its label, so that the fields line up in the
    /// same place whatever a tab happens to call them.
    @Entry var formLabelWidth: CGFloat = 0

    /// What a row of prose may fill: everything from where the fields begin
    /// to the far side of the form.
    @Entry var formProseWidth: CGFloat = 0
}

extension FormStack where Header == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.header = EmptyView()
        self.content = content()
    }
}

extension View {
    /// Marks this view as a form row's control.
    func fieldControl() -> some View {
        frame(width: .fieldControlWidth, alignment: .leading)
    }

    /// Marks this view as a form row's prose, which wraps in what the form
    /// leaves to the right of its fields rather than in a field's width.
    func fieldProse() -> some View {
        modifier(FieldProse())
    }
}

/// The row keeps the width the form gave it, so the fields stay where they
/// are; the prose inside runs on into what the form leaves beside them.
private struct FieldProse: ViewModifier {
    @Environment(\.formProseWidth) private var proseWidth

    func body(content: Content) -> some View {
        content
            .frame(
                width: max(.fieldControlWidth, proseWidth),
                alignment: .leading
            )
    }
}
