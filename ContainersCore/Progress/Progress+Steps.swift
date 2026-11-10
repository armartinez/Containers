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

    /// Counts bytes when there's a byte total, otherwise items, and never moves back. Each
    /// handler keeps its own tally, so share one per step. Updates after the step completes
    /// are dropped.
    public func updateHandler() -> ProgressHandler {
        let tally = OSAllocatedUnfairLock(initialState: Tally())

        return { [self] events in
            tally.withLock { tally in
                guard let reading = tally.update(with: events) else { return }

                whileOpen {
                    if reading.measuresBytes {
                        kind = .file
                    }

                    totalUnitCount = reading.total
                    // A step finished early counts twice towards its parent, so only
                    // `complete()` finishes it.
                    completedUnitCount = min(
                        Int64(reading.fraction * Double(reading.total)),
                        reading.total - 1
                    )
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
    private var items = Count()
    private var bytes = Count()

    private static let smallestMeasuredStage: Int64 = 1024 * 1024

    /// The highest fraction shown so far.
    private var shown = 0.0
    private var stage = Stage()

    struct Count {
        var completed: Int64 = 0
        var total: Int64 = 0
    }

    struct Reading {
        let total: Int64
        let fraction: Double
        let measuresBytes: Bool
    }

    /// The work counted since the total last changed, with the fraction shown at that point.
    private struct Stage {
        var total: Int64 = 0
        var measuresBytes = false
        var start: Int64 = 0
        var shown = 0.0
    }

    private var measure: Count? {
        if bytes.total > 0 { return bytes }
        if items.total > 0 { return items }

        return nil
    }

    /// `nil` leaves the step as it is: nothing is measured yet, or the count has caught up with a total that may still grow.
    mutating func update(with events: [ProgressEvent]) -> Reading? {
        let itemsBefore = items.completed
        let bytesBefore = bytes.completed

        add(events)

        guard let count = measure else { return nil }

        let measuresBytes = bytes.total > 0

        // Totals arrive in stages (an image's index, then its manifest, then its layers), so
        // a new total spreads its work over what's left instead of moving progress back.
        if count.total != stage.total || measuresBytes != stage.measuresBytes {
            stage = Stage(
                total: count.total,
                measuresBytes: measuresBytes,
                start: measuresBytes ? bytesBefore : itemsBefore,
                shown: shown
            )
        }

        guard count.completed < count.total else { return nil }

        // Containerization fetches blobs under 1 MiB (an image's index, manifests and configs)
        // whole, ahead of the layers. Counting them would fill the bar before the layers are known.
        if measuresBytes && count.total - stage.start < Self.smallestMeasuredStage {
            return nil
        }

        let done = Double(count.completed - stage.start) / Double(count.total - stage.start)

        shown = max(shown, stage.shown + (1 - stage.shown) * done)

        return Reading(total: count.total, fraction: shown, measuresBytes: measuresBytes)
    }

    private mutating func add(_ events: [ProgressEvent]) {
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
