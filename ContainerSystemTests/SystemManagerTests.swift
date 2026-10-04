//
//  SystemManagerTests.swift
//  ContainerSystemTests
//
//  Stopping a start that is under way.
//

import Foundation
import Testing

@testable import ContainerSystem

/// A start that never finishes of its own accord, so that only cancelling
/// brings it to an end.
@MainActor
private final class NeverFinishingRuntime: ContainerRuntime {
    private(set) var didFinish = false

    init() {
        super.init(forTesting: true)
    }

    override func start(appRoot: URL) async throws {
        isStarting = true

        defer {
            isStarting = false
        }

        try await Task.sleep(for: .seconds(30))

        didFinish = true
    }
}

@Suite("System manager")
@MainActor
struct SystemManagerTests {

    /// The sheet that offers to stop a first run is not always the thing that
    /// began it: the dashboard starts the system on later launches and the
    /// sheet only opens onto the work. Cancelling has to reach it either way.
    @Test("Cancel start begun elsewhere")
    func cancelsStartBegunElsewhere() async throws {
        let runtime = NeverFinishingRuntime()
        let system = SystemManager(testRuntime: runtime)

        // Whoever is waiting here never cancels its own task, the way the
        // dashboard's start task does not.
        let work = Task { try await system.start(appRoot: .temporaryDirectory) }

        while system.status != .starting {
            try await Task.sleep(for: .milliseconds(10))
        }

        system.cancelStart()

        await #expect(throws: CancellationError.self) {
            try await work.value
        }

        #expect(runtime.didFinish == false)
        #expect(system.status == .notStarted)
    }

    @Test("Cancel start from caller")
    func cancelsStartFromTheCaller() async throws {
        let runtime = NeverFinishingRuntime()
        let system = SystemManager(testRuntime: runtime)

        let work = Task { try await system.start(appRoot: .temporaryDirectory) }

        while system.status != .starting {
            try await Task.sleep(for: .milliseconds(10))
        }

        work.cancel()

        await #expect(throws: CancellationError.self) {
            try await work.value
        }

        #expect(runtime.didFinish == false)
    }

    @Test("Cancel with nothing starting")
    func cancelsNothingSafely() {
        let system = SystemManager(testRuntime: NeverFinishingRuntime())

        system.cancelStart()

        #expect(system.status == .notStarted)
    }
}
