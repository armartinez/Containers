//
//  TextField+Suggestions.swift
//  Containers
//
//  Created by Axel Martinez on 01/08/2026.
//

import SwiftUI

extension TextField {
    /// Suggests completions for `text` once typing stops, while `isEnabled`, such as while the field has focus.
    /// On `TextField`, so it must come first in the modifier chain.
    func suggestions(
        for text: String,
        isEnabled: Bool,
        fetch: @escaping @Sendable (String) async throws -> [String]
    ) -> some View {
        modifier(TextFieldSuggestions(text: text, isEnabled: isEnabled, fetch: fetch))
    }
}

private struct TextFieldSuggestions: ViewModifier {
    private static let debounce: Duration = .milliseconds(300)

    let text: String
    let isEnabled: Bool
    let fetch: @Sendable (String) async throws -> [String]

    @SwiftUI.State private var suggestions: [String] = []
    @SwiftUI.State private var isLoading = false

    /// Set when the last lookup failed, as opposed to matching nothing.
    @SwiftUI.State private var failure: String?

    @SwiftUI.State private var cache = SuggestionCache()

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .trailing) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 6)
                } else if let failure {
                    // An empty menu otherwise reads as "nothing matched".
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(failure)
                        .padding(.trailing, 6)
                        .accessibilityLabel(failure)
                }
            }
            .textInputSuggestions {
                ForEach(suggestions, id: \.self) { suggestion in
                    Text(suggestion)
                        .textInputCompletion(suggestion)
                }
            }
            // A new text cancels the lookup for the previous one.
            .task(id: text) {
                await lookUp()
            }
    }

    private func lookUp() async {
        // Picking a suggestion sets the text to it, and looking that up would open the menu again.
        // Losing focus clears nothing, since the system hides the menu, and picking can move focus.
        guard isEnabled, !text.isEmpty, !suggestions.contains(text) else {
            suggestions = []
            failure = nil
            isLoading = false
            return
        }

        do {
            try await Task.sleep(for: Self.debounce)
        } catch {
            return
        }

        if let cached = cache.values(for: text) {
            suggestions = cached
            failure = nil
            isLoading = false
            return
        }

        isLoading = true

        do {
            let results = try await fetch(text)

            // URL loading reports cancellation as its own error, or not at all.
            guard !Task.isCancelled else { return }

            cache.store(results, for: text)
            suggestions = results
            failure = nil
        } catch {
            guard !Task.isCancelled else { return }

            // Not cached, so retyping retries.
            suggestions = []
            failure = error.localizedDescription
        }

        isLoading = false
    }
}

/// Lets backspacing answer from memory instead of the network.
private struct SuggestionCache {
    private struct Entry {
        let values: [String]
        let stored: ContinuousClock.Instant
    }

    private let ttl: Duration = .seconds(120)
    private let limit = 32

    private var entries: [String: Entry] = [:]

    func values(for text: String) -> [String]? {
        guard let entry = entries[text],
            entry.stored.duration(to: ContinuousClock.now) < ttl
        else {
            return nil
        }

        return entry.values
    }

    mutating func store(_ values: [String], for text: String) {
        entries[text] = Entry(values: values, stored: ContinuousClock.now)

        guard entries.count > limit else {
            return
        }

        // Expired entries first, then the oldest.
        let now = ContinuousClock.now
        entries = entries.filter { $0.value.stored.duration(to: now) < ttl }

        guard entries.count > limit else {
            return
        }

        let excess =
            entries
            .sorted { $0.value.stored < $1.value.stored }
            .prefix(entries.count - limit)

        for entry in excess {
            entries[entry.key] = nil
        }
    }
}
