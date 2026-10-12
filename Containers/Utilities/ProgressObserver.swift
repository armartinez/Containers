//
//  ProgressObserver.swift
//  Containers
//
//  Created by Axel Martinez on 2026/10/02.
//

import Foundation
import Observation
import os

/// A `Progress` as SwiftUI can watch it.
///
/// `Progress` reports changes through key-value observing, on whichever thread
/// made them; this repeats what it says on the main actor, at most once for
/// each turn of it however many changes arrive in between.
@Observable
@MainActor
final class ProgressObserver {
    let progress: Progress

    /// `nil` while nobody knows how much there is to do.
    private(set) var fractionCompleted: Double?
    private(set) var localizedDescription = ""
    private(set) var localizedAdditionalDescription = ""

    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init(_ progress: Progress) {
        self.progress = progress
        refresh()
        observations = Self.observe(progress) { [weak self] in
            self?.refresh()
        }
    }

    private func refresh() {
        // TODO: Review this implementation
        // A step's handler sets its total and then its count, in two writes, on whichever thread
        // reports progress. This runs on the main actor whenever it's scheduled, without taking
        // the handler's lock, so it can read between the two: the new, larger total against the
        // old count, which shows less done than before. A run only moves forward, so keep the
        // highest fraction seen.
        fractionCompleted = progress.isIndeterminate ? nil : max(fractionCompleted ?? 0, progress.fractionCompleted)
        localizedDescription = progress.localizedDescription ?? ""
        localizedAdditionalDescription = progress.localizedAdditionalDescription ?? ""
    }

    private nonisolated static func observe(
        _ progress: Progress,
        onChange: @escaping @MainActor () -> Void
    ) -> [NSKeyValueObservation] {
        let isScheduled = OSAllocatedUnfairLock(initialState: false)

        let changed: @Sendable () -> Void = {
            let schedule = isScheduled.withLock { isScheduled in
                defer { isScheduled = true }
                return !isScheduled
            }

            guard schedule else { return }

            Task { @MainActor in
                isScheduled.withLock { $0 = false }
                onChange()
            }
        }

        return [
            progress.observe(\.fractionCompleted) { _, _ in changed() },
            progress.observe(\.isIndeterminate) { _, _ in changed() },
            progress.observe(\.localizedDescription) { _, _ in changed() },
            progress.observe(\.localizedAdditionalDescription) { _, _ in changed() },
        ]
    }
}
