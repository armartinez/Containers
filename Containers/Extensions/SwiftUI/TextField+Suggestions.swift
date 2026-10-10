//
//  TextField+Suggestions.swift
//  Containers
//
//  Created by Axel Martinez on 01/08/2026.
//

import Combine
import SwiftUI

extension TextField {
    /// Suggests completions for `text` once typing stops; `nil` cancels and closes the menu.
    /// On `TextField`, so it must come first in the modifier chain.
    func suggestions(
        for text: String?,
        fetch: @escaping @Sendable (String) async throws -> [String]
    ) -> some View {
        modifier(TextFieldSuggestions(text: text, fetch: fetch))
    }
}

private struct TextFieldSuggestions: ViewModifier {
    let text: String?
    let fetch: @Sendable (String) async throws -> [String]

    @SwiftUI.State private var resolver = SuggestionResolver()

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .trailing) {
                if resolver.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 6)
                } else if let failure = resolver.failure {
                    // An empty menu otherwise reads as "nothing matched".
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(failure)
                        .padding(.trailing, 6)
                        .accessibilityLabel(failure)
                }
            }
            .textInputSuggestions {
                ForEach(resolver.suggestions, id: \.self) { suggestion in
                    Text(suggestion)
                        .textInputCompletion(suggestion)
                }
            }
            .onChange(of: text) { _, newText in
                // Text matching a suggestion was just picked from the menu.
                guard let newText, !newText.isEmpty,
                    !resolver.suggestions.contains(newText)
                else {
                    resolver.reset()
                    return
                }

                resolver.send(newText, using: fetch)
            }
            .onDisappear {
                resolver.reset()
            }
    }
}

/// Debounces typing into at most one lookup, skipping text already loaded.
@Observable
private final class SuggestionResolver {
    private(set) var suggestions: [String] = []
    private(set) var isLoading = false

    /// Set when the last lookup failed, as opposed to matching nothing.
    private(set) var failure: String?

    private let queries = PassthroughSubject<String?, Never>()

    /// Cleared on reset, so the text alone can be the key.
    @ObservationIgnored private var cache = SuggestionCache()
    @ObservationIgnored private var fetch: (@Sendable (String) async throws -> [String])?
    @ObservationIgnored private var subscription: AnyCancellable?
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var loadedText: String?

    init(debounce: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(300)) {
        self.subscription =
            queries
            .debounce(for: debounce, scheduler: DispatchQueue.main)
            .sink { [weak self] text in
                MainActor.assumeIsolated {
                    guard let text else { return }
                    self?.load(text)
                }
            }
    }

    /// Takes the lookup every time, so it never goes stale against the view.
    func send(
        _ text: String,
        using fetch: @escaping @Sendable (String) async throws -> [String]
    ) {
        self.fetch = fetch
        queries.send(text)
    }

    func reset() {
        queries.send(nil)
        fetchTask?.cancel()
        fetchTask = nil
        loadedText = nil
        suggestions = []
        failure = nil
        isLoading = false
        cache.removeAll()
    }

    private func load(_ text: String) {
        guard text != loadedText, let fetch else { return }

        fetchTask?.cancel()
        loadedText = text

        if let cached = cache.values(for: text) {
            suggestions = cached
            failure = nil
            isLoading = false
            return
        }

        isLoading = true

        fetchTask = Task {
            do {
                let results = try await fetch(text)

                // The newer text owns `isLoading` now.
                guard !Task.isCancelled else { return }

                cache.store(results, for: text)
                suggestions = results
                failure = nil
                isLoading = false
            } catch {
                guard !Task.isCancelled else { return }

                // Not cached, so retyping retries.
                loadedText = nil
                suggestions = []
                failure = error.localizedDescription
                isLoading = false
            }
        }
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

    mutating func removeAll() {
        entries.removeAll()
    }
}
