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
        fractionCompleted = progress.isIndeterminate ? nil : progress.fractionCompleted
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
