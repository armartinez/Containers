//
//  View+RowTint.swift
//  Containers
//
//  Created by Axel Martinez on 15/09/2026.
//

import SwiftUI

extension View {
    /// On a selected row, takes the row's foreground instead, as Finder's marks turn white.
    func rowTint(_ color: Color) -> some View {
        modifier(RowTint(color: color))
    }
}

private struct RowTint: ViewModifier {
    let color: Color

    @Environment(\.backgroundProminence) private var backgroundProminence

    func body(content: Content) -> some View {
        content.foregroundStyle(
            backgroundProminence == .increased
                ? AnyShapeStyle(HierarchicalShapeStyle.primary)
                : AnyShapeStyle(color)
        )
    }
}
