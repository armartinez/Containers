//
//  FilterField.swift
//  Containers
//
//  Created by Axel Martinez on 02/08/2026.
//

import AppKit
import SwiftUI

/// The filter bar AppKit puts at the top of its lists and menus: a flat grey
/// field that takes on a text field's face once it has focus.
struct FilterField: View {
    @Binding var text: String
    var cornerRadius: CGFloat = 6
    var horizontalPadding: CGFloat = 6
    var verticalPadding: CGFloat = 3
    var highlightsActiveFilter: Bool = true

    @FocusState private var isFocused: Bool

    private var isFiltering: Bool {
        highlightsActiveFilter && !text.isEmpty
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(
                systemName: isFiltering
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
            // `Color.accentColor` desaturates wherever SwiftUI reads the
            // control state as inactive, which is what a popover's own window
            // reports; the raw system accent keeps its colour there.
            .foregroundStyle(
                isFiltering
                    ? Color(nsColor: .controlAccentColor) : Color.secondary
            )
            .font(.system(size: 12))

            TextField("Filter", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(
            Color(
                nsColor: isFocused
                    ? .textBackgroundColor : .quaternaryLabelColor
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        Color(nsColor: .separatorColor),
                        lineWidth: 1
                    )
            }
        }
    }
}
