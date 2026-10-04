//
//  Progress+Steps.swift
//  Containers
//
//  Created by Axel Martinez on 2026/10/02.
//

import ContainerizationExtras
import Foundation
import os

/// A method handed a progress sets `totalUnitCount` to its steps and runs each with `performStep`.
extension Progress {
    /// Runs `work` as a child worth `pendingUnitCount`, mirroring the step's descriptions here
    /// so the top progress describes the deepest step.
    public func performStep<T>(
        _ description: String = "",
        pendingUnitCount: Int64 = 1,
        isolation: isolated (any Actor)? = #isolation,
        _ work: (Progress) async throws -> T
    ) async throws -> T {
        let step = Step(parent: nil)
        step.localizedDescription = description
        addChild(step, withPendingUnitCount: pendingUnitCount)

        let observations = mirror(step)
        let result: T

        do {
            result = try await work(step)
        } catch {
            for observation in observations {
                observation.invalidate()
            }

            throw error
        }

        // Before completing, or an unmeasured step would show "1 of 1" here.
        for observation in observations {
            observation.invalidate()
        }

        step.complete()

        return result
    }

    /// Counts bytes when there's a byte total, otherwise items. Each handler keeps its own
    /// tally, so share one per step. Reports after the step completes are dropped.
    public func updateHandler() -> ProgressHandler {
        let tally = OSAllocatedUnfairLock(initialState: Tally())

        return { [self] events in
            tally.withLock { tally in
                tally.add(events)

                guard let count = tally.measure else { return }

                whileOpen {
                    if tally.bytes.total > 0 {
                        kind = .file
                    }

                    totalUnitCount = count.total
                    // Totals can grow after catching up, and a step finished early
                    // counts twice towards its parent, so only `complete()` finishes it.
                    completedUnitCount = min(count.completed, count.total - 1)
                }
            }
        }
    }

    func complete() {
        whileOpen(closing: true) {
            if totalUnitCount <= 0 {
                totalUnitCount = 1
            }

            // Setting it again once finished removes it from its parent.
            guard completedUnitCount < totalUnitCount else { return }

            completedUnitCount = totalUnitCount
        }
    }

    /// Skips `body` once a step has completed; other progresses are always open.
    private func whileOpen(closing: Bool = false, _ body: () -> Void) {
        guard let step = self as? Step else {
            body()
            return
        }

        step.isOpen.withLockUnchecked { isOpen in
            guard isOpen else { return }

            body()

            if closing {
                isOpen = false
            }
        }
    }

    private func mirror(_ step: Progress) -> [NSKeyValueObservation] {
        [
            step.observe(\.localizedDescription, options: .initial) { [self] step, _ in
                localizedDescription = step.localizedDescription
            },
            step.observe(\.localizedAdditionalDescription, options: .initial) { [self] step, _ in
                localizedAdditionalDescription = step.localizedAdditionalDescription
            },
        ]
    }
}

private final class Step: Progress, @unchecked Sendable {
    let isOpen = OSAllocatedUnfairLock(initialState: true)
}

private struct Tally {
    var items = Count()
    var bytes = Count()

    struct Count {
        var completed: Int64 = 0
        var total: Int64 = 0
    }

    var measure: Count? {
        if bytes.total > 0 { return bytes }
        if items.total > 0 { return items }

        return nil
    }

    mutating func add(_ events: [ProgressEvent]) {
        for event in events {
            switch event {
            case .addItems(let count): items.completed += Int64(count)
            case .addTotalItems(let count): items.total += Int64(count)
            case .addSize(let size): bytes.completed += size
            case .addTotalSize(let size): bytes.total += size
            }
        }
    }
}
