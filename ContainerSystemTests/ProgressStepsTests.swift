//
//  ProgressStepsTests.swift
//  ContainerSystemTests
//
//  How an operation counts its steps into a Progress.
//

import ContainerizationExtras
import Foundation
import Testing

@testable import ContainerSystem

@Suite("Progress steps")
@MainActor
struct ProgressStepsTests {

    @Test("Step description shows on parent")
    func showsStepDescription() async throws {
        let progress = Progress(totalUnitCount: 2)

        try await progress.performStep("Fetching image") { _ in
            #expect(progress.localizedDescription == "Fetching image")
        }

        try await progress.performStep("Unpacking image") { _ in
            #expect(progress.localizedDescription == "Unpacking image")
        }
    }

    @Test("Deepest step describes the operation")
    func deepestStepWins() async throws {
        let progress = Progress(totalUnitCount: 1)

        try await progress.performStep("Starting builder") { builder in
            builder.totalUnitCount = 1

            try await builder.performStep("Fetching builder image") { step in
                await step.updateHandler()([.addTotalItems(4), .addItems(1)])

                #expect(progress.localizedDescription == "Fetching builder image")
                #expect(progress.localizedAdditionalDescription == "1 of 4")
            }
        }
    }

    @Test("Steps share the total")
    func stepsShareTheOperation() async throws {
        let progress = Progress(totalUnitCount: 2)

        try await progress.performStep("Fetching image") { step in
            await step.updateHandler()([.addTotalItems(4), .addItems(2)])

            #expect(progress.fractionCompleted == 0.25)
        }

        #expect(progress.fractionCompleted == 0.5)
    }

    @Test("Unmeasured step completes")
    func unmeasuredStepCompletes() async throws {
        let progress = Progress(totalUnitCount: 2)

        try await progress.performStep("Creating container") { step in
            #expect(step.isIndeterminate)
        }

        #expect(progress.fractionCompleted == 0.5)
    }

    @Test("Failed step doesn't complete")
    func failedStepDoesNotComplete() async {
        struct Failure: Error {}

        let progress = Progress(totalUnitCount: 2)

        await #expect(throws: Failure.self) {
            try await progress.performStep("Fetching image") { _ in
                throw Failure()
            }
        }

        #expect(progress.fractionCompleted == 0)
    }

    @Test("Finished step stops mirroring")
    func finishedStepStopsMirroring() async throws {
        let progress = Progress(totalUnitCount: 2)
        var finished: Progress?

        try await progress.performStep("Fetching image") { step in
            finished = step
        }

        finished?.localizedDescription = "Stale"

        #expect(progress.localizedDescription == "Fetching image")
        // Completing an unmeasured step does not say "1 of 1" here.
        #expect(progress.localizedAdditionalDescription == "")
    }

    @Test("Late reports are dropped")
    func lateReportsAreDropped() async throws {
        let progress = Progress(totalUnitCount: 2)
        var update: ProgressHandler?

        try await progress.performStep("Fetching image") { step in
            update = step.updateHandler()
            await update?([.addTotalItems(4), .addItems(4)])
        }

        #expect(progress.fractionCompleted == 0.5)

        await update?([.addTotalItems(4), .addItems(1)])

        #expect(progress.fractionCompleted == 0.5)
        #expect(progress.completedUnitCount == 1)
    }

    @Test("Bytes take precedence over items")
    func bytesOverItems() async {
        let progress = Progress(totalUnitCount: 0)
        let update = progress.updateHandler()

        await update([.addTotalItems(10), .addItems(5)])

        #expect(progress.fractionCompleted == 0.5)

        await update([.addTotalSize(10_000_000), .addSize(1_000_000)])

        #expect(progress.kind == .file)
        #expect(progress.totalUnitCount == 10_000_000)
        #expect(progress.fractionCompleted == 0.55)
    }

    @Test("Staged totals never move progress back")
    func stagedTotalsStayMonotonic() async throws {
        let progress = Progress(totalUnitCount: 1)
        var fractions: [Double] = []

        try await progress.performStep("Fetching image") { step in
            let update = step.updateHandler()
            // How an image pull reports: the index, then a manifest per platform, then the configs and layers.
            let batches: [[ProgressEvent]] = [
                [.addTotalSize(10_000), .addTotalItems(1)],
                [.addSize(10_000), .addItems(1)],
                [.addTotalSize(30_000), .addTotalItems(3)],
                [.addSize(10_000), .addItems(1)],
                [.addSize(10_000), .addItems(1)],
                [.addSize(10_000), .addItems(1)],
                [.addTotalSize(4_000_000), .addTotalItems(2)],
                [.addSize(1_000_000)],
                [.addSize(2_000_000)],
                [.addSize(1_000_000), .addItems(2)],
            ]

            for batch in batches {
                await update(batch)
                fractions.append(progress.fractionCompleted)
            }
        }

        #expect(fractions == fractions.sorted())
        #expect(fractions[0...6].allSatisfy { $0 == 0 })
        #expect(fractions[8] == 0.75)
        #expect(progress.fractionCompleted == 1)
    }

    @Test("Counts without a total stay indeterminate")
    func countsWithoutTotal() async {
        let progress = Progress(totalUnitCount: 0)

        await progress.updateHandler()([.addItems(3)])

        #expect(progress.isIndeterminate)
    }

    @Test("Handler accumulates counts")
    func handlerAccumulates() async {
        let progress = Progress(totalUnitCount: 0)
        let update = progress.updateHandler()

        await update([.addTotalItems(4), .addItems(1)])
        await update([.addItems(1)])

        #expect(progress.totalUnitCount == 4)
        #expect(progress.completedUnitCount == 2)
    }

    @Test("Overshoot is capped")
    func overshootIsCapped() async throws {
        let progress = Progress(totalUnitCount: 1)

        try await progress.performStep("Fetching image") { step in
            await step.updateHandler()([.addTotalItems(2), .addItems(5)])

            #expect(progress.fractionCompleted < 1)
        }

        #expect(progress.fractionCompleted == 1)
    }

    @Test("Growing total counts once")
    func totalGrowingAfterCatchingUp() async throws {
        let progress = Progress(totalUnitCount: 2)

        try await progress.performStep("Fetching image") { step in
            let update = step.updateHandler()

            await update([.addTotalItems(2), .addItems(2)])
            await update([.addTotalItems(2), .addItems(2)])
        }

        #expect(progress.fractionCompleted == 0.5)

        try await progress.performStep("Unpacking image") { _ in
            #expect(progress.fractionCompleted == 0.5)
        }

        #expect(progress.fractionCompleted == 1)
    }
}
