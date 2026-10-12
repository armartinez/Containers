//
//  ScopeBar.swift
//  Containers
//
//  Created by Axel Martinez on 21/09/2026.
//

import SwiftUI

/// Narrows what is shown below it: scopes on the left, actions and the filter on the right.
struct ScopeBar<Leading: View, Trailing: View>: View {
    /// `nil` where the window's own search field filters instead.
    var filter: Binding<String>?

    /// Off in a titlebar, which supplies its own backdrop.
    var drawsBackground = true

    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                leading

                Spacer(minLength: 8)

                trailing

                if let filter {
                    FilterField(text: filter, verticalPadding: 2)
                        .frame(width: 180)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: .barHeight)

            Divider()
        }
        .background(drawsBackground ? AnyShapeStyle(.bar) : AnyShapeStyle(.clear))
    }
}

extension ScopeBar where Trailing == EmptyView {
    init(
        filter: Binding<String>? = nil,
        @ViewBuilder leading: () -> Leading
    ) {
        self.init(filter: filter, leading: leading) { EmptyView() }
    }
}
