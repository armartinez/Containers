//
//  View+HoverHighlight.swift
//  Containers
//
//  Created by Axel Martinez on 2026/10/30.
//

import SwiftUI

extension View {
    /// Fills the view's background while the pointer is over it, as a borderless pop-up does in System Settings.
    func hoverHighlight() -> some View {
        modifier(HoverHighlight())
    }
}

private struct HoverHighlight: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.quaternary)
                    .opacity(isHovered && isEnabled ? 1 : 0)
            }
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
