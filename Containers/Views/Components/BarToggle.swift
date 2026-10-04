//
//  BarToggle.swift
//  Containers
//
//  Created by Axel Martinez on 21/09/2026.
//

import SwiftUI

/// A toggle for bars: one of several choices, or a standalone switch.
/// Shared by every bar so their padding and fills stay identical.
struct BarToggle: View {
    enum Manner {
        /// Secondary until selected or hovered.
        case choice
        /// Picks what's shown below the bar; the selected one is filled with the accent colour.
        case tab
        /// A standalone on/off button.
        case control
        /// A sheet's tabs: the selected one is tinted rather than filled.
        case segment
    }

    let title: String
    var manner: Manner = .choice

    @Binding var isOn: Bool

    @State private var isHovered = false

    var body: some View {
        Group {
            switch manner {
            case .choice, .tab, .segment: word
            case .control: control
            }
        }
        .font(.callout)
    }

    private static let cornerRadius: CGFloat = 5

    private var word: some View {
        Button {
            isOn = true
        } label: {
            Text(title)
        }
        .buttonStyle(
            WordStyle(
                foreground: foreground,
                background: background,
                pressed: pressed,
                cornerRadius: Self.cornerRadius
            )
        )
        .onHover { isHovered = $0 }
    }

    private var pressed: Color {
        // Between quaternary (the hover) and tertiary, which reads as a stain.
        isOn ? background : Color(nsColor: .tertiaryLabelColor).opacity(0.6)
    }

    /// A custom style, since the plain style doesn't expose the pressed state.
    private struct WordStyle: ButtonStyle {
        let foreground: AnyShapeStyle
        let background: Color
        let pressed: Color
        let cornerRadius: CGFloat

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundStyle(foreground)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(configuration.isPressed ? pressed : background)
                )
                .contentShape(Rectangle())
        }
    }

    private var control: some View {
        Toggle(title, isOn: $isOn)
            .toggleStyle(.button)
            .buttonStyle(.accessoryBar)
            // Accessory bar buttons are 4pt taller than the filter field; small matches it.
            .controlSize(.small)
    }

    private var foreground: AnyShapeStyle {
        switch manner {
        case .tab where isOn:
            AnyShapeStyle(Color(nsColor: .alternateSelectedControlTextColor))
        case .segment where isOn:
            AnyShapeStyle(Color(nsColor: .controlAccentColor))
        case .choice where !isOn && !isHovered:
            AnyShapeStyle(.secondary)
        default:
            AnyShapeStyle(.primary)
        }
    }

    private var background: Color {
        if isOn {
            // `Color.accentColor` desaturates when SwiftUI reads the control as
            // inactive; the system accent keeps its colour.
            switch manner {
            case .tab:
                return Color(nsColor: .controlAccentColor)
            case .segment:
                return Color(nsColor: .controlAccentColor).opacity(0.15)
            default:
                return Color(
                    nsColor: .unemphasizedSelectedContentBackgroundColor
                )
            }
        }

        // Unselected tabs keep a fill instead of a hover effect, so every
        // destination stays visible without pointing at it.
        guard manner != .tab else { return Color(nsColor: .quinaryLabelColor) }

        // Lighter than the press, so hovering reads as less than choosing.
        return isHovered ? Color(nsColor: .quaternaryLabelColor) : .clear
    }
}

extension BarToggle {
    /// On while `selection` equals `value`. It can't be turned off, since one is always selected.
    init<Value: Equatable>(
        _ title: String,
        selection: Binding<Value>,
        value: Value,
        manner: Manner = .choice
    ) {
        self.init(
            title: title,
            manner: manner,
            isOn: Binding(
                get: { selection.wrappedValue == value },
                set: { isOn in
                    guard isOn else { return }

                    selection.wrappedValue = value
                }
            )
        )
    }
}
