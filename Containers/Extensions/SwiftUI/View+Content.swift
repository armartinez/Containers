//
//  View+Content.swift
//  Containers
//
//  Created by Axel Martinez on 01/08/2026.
//

import SwiftUI

/// What a view declares about its size to a `Layout` that sizes it or its window.
/// Layout values, not preferences, which would arrive a pass late.
extension View {
    /// Until ready, the layout keeps its size rather than fit a half-drawn view.
    /// Apply to the outermost view: a value set inside a stack belongs to that stack.
    func contentReady(_ isReady: Bool) -> some View {
        layoutValue(key: ContentReadyKey.self, value: isReady)
    }

    /// For content with no height of its own, such as a scroll view or an
    /// `NSViewRepresentable`; the layout bounds it instead of asking.
    func contentUnbounded(_ isUnbounded: Bool = true) -> some View {
        layoutValue(key: ContentUnboundedKey.self, value: isUnbounded)
    }

    /// The natural size of content that can't report it through `sizeThatFits`,
    /// such as a scroll view. Zero on an axis means ask the usual way.
    func contentIdealSize(_ size: CGSize) -> some View {
        layoutValue(key: ContentIdealSizeKey.self, value: size)
    }
}

extension LayoutSubview {
    /// True for content that never declared it.
    nonisolated var isContentReady: Bool {
        self[ContentReadyKey.self]
    }

    /// Asking such a subview its ideal size runs a nested AppKit layout.
    nonisolated var isContentUnbounded: Bool {
        self[ContentUnboundedKey.self]
    }

    nonisolated var contentIdealSize: CGSize {
        self[ContentIdealSizeKey.self]
    }
}

private struct ContentReadyKey: LayoutValueKey {
    nonisolated static let defaultValue = true
}

private struct ContentUnboundedKey: LayoutValueKey {
    nonisolated static let defaultValue = false
}

private struct ContentIdealSizeKey: LayoutValueKey {
    nonisolated static let defaultValue: CGSize = .zero
}
