//
//  ContainerSystemTests.swift
//  ContainersCoreTests
//
//  Starting and stopping the container system, and stopping a start that is under way.
//

import Foundation
import Testing

@testable import ContainersCore

/// A start that never finishes of its own accord, so that only cancelling
/// brings it to an end.
@MainActor
private final class NeverFinishingSystem: ContainerSystem {
    private(set) var didFinish = false

    init() {
        super.init()
    }

    override func launch(appRoot: URL, readOnly: Bool, installingKernel: Bool) async throws {
        status = .starting

        defer {
            settleStopped()
        }

        try await Task.sleep(for: .seconds(30))

        didFinish = true
    }
}

/// Needs the kernel for a system of its own, as the real system does, but not to read the CLI's folder.
@MainActor
private final class MissingKernelSystem: ContainerSystem {
    init(cliStatus: (@Sendable () async throws -> ContainerCLI.Status)? = nil) {
        if let cliStatus {
            super.init(cliStatus: cliStatus)
        } else {
            super.init()
        }
    }

    override func launch(appRoot: URL, readOnly: Bool, installingKernel: Bool) async throws {
        guard readOnly else {
            startupError = ContainerSystem.SetupError.kernelInstallNotConfirmed
            throw ContainerSystem.SetupError.kernelInstallNotConfirmed
        }

        startupError = nil
        status = .readOnly
    }
}

@Suite("Container system", .serialized)
@MainActor
struct ContainerSystemTests {

    @Test("Start system")
    func startSystem() async throws {
        let containerSystem = MockContainerSystem()

        let appRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-containers-\(UUID().uuidString)")

        try await containerSystem.start(appRoot: appRoot)

        #expect(containerSystem.status == .running)

        try await containerSystem.stop()
    }

    @Test("Start twice")
    func startTwice() async throws {
        let containerSystem = MockContainerSystem()

        let appRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-containers-\(UUID().uuidString)")

        try await containerSystem.start(appRoot: appRoot)
        #expect(containerSystem.status == .running)

        // Starting again should not cause error
        try await containerSystem.start(appRoot: appRoot)
        #expect(containerSystem.status == .running)

        try await containerSystem.stop()
    }

    @Test("Stop system")
    func stopSystem() async throws {
        let containerSystem = MockContainerSystem()

        // Ensure system is started
        let appRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-containers-\(UUID().uuidString)")

        try await containerSystem.start(appRoot: appRoot)
        #expect(containerSystem.status == .running)

        // Stop the system
        try await containerSystem.stop()

        #expect(containerSystem.status == .notStarted)
    }

    /// The sheet that offers to stop a first run is not always the thing that
    /// began it: the dashboard starts the system on later launches and the
    /// sheet only opens onto the work. Cancelling has to reach it either way.
    @Test("Cancel start begun elsewhere")
    func cancelsStartBegunElsewhere() async throws {
        let containerSystem = NeverFinishingSystem()

        // Whoever is waiting here never cancels its own task, the way the
        // dashboard's start task does not.
        let work = Task { try await containerSystem.start(appRoot: .temporaryDirectory) }

        while containerSystem.status != .starting {
            try await Task.sleep(for: .milliseconds(10))
        }

        containerSystem.cancelStart()

        await #expect(throws: CancellationError.self) {
            try await work.value
        }

        #expect(containerSystem.didFinish == false)
        #expect(containerSystem.status == .notStarted)
    }

    @Test("Cancel start from caller")
    func cancelsStartFromTheCaller() async throws {
        let containerSystem = NeverFinishingSystem()

        let work = Task { try await containerSystem.start(appRoot: .temporaryDirectory) }

        while containerSystem.status != .starting {
            try await Task.sleep(for: .milliseconds(10))
        }

        work.cancel()

        await #expect(throws: CancellationError.self) {
            try await work.value
        }

        #expect(containerSystem.didFinish == false)
    }

    @Test("Doesn't download the kernel until asked to")
    func waitsForKernelConfirmation() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let containerSystem = MockContainerSystem()
        try await containerSystem.launch(appRoot: directory.url, readOnly: false, installingKernel: false)

        await #expect(throws: ContainerSystem.SetupError.kernelInstallNotConfirmed) {
            try await containerSystem.installPrerequisites(installingKernel: false)
        }

        #expect(containerSystem.setupProgress == nil)

        try await containerSystem.shutdown()
    }

    @Test("A start waiting for the kernel leaves the system stopped")
    func reportsKernelConfirmation() {
        let containerSystem = MockContainerSystem()

        containerSystem.startupError = ContainerSystem.SetupError.kernelInstallNotConfirmed

        // Stopped, not failed: the kernel is asked about when the user starts the system.
        #expect(containerSystem.status == .notStarted)
        #expect(containerSystem.needsKernelConfirmation)
    }

    @Test("A start of a system of its own stops for the kernel")
    func stopsForKernelWhenCLIIsStopped() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        try writeAPIServerPlist(in: directory.url)

        let containerSystem = MissingKernelSystem()
        containerSystem.mode = .cliCompatibility

        await #expect(throws: ContainerSystem.SetupError.kernelInstallNotConfirmed) {
            try await containerSystem.start(appRoot: directory.url)
        }

        #expect(containerSystem.needsKernelConfirmation)
        #expect(containerSystem.status == .notStarted)
    }

    @Test("A start beside the running CLI needs no kernel, even after one stopped for it")
    func skipsKernelWhileCLIRuns() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        try writeAPIServerPlist(in: directory.url)

        let appRoot = directory.url
        let containerSystem = MissingKernelSystem {
            ContainerCLI.Status(isInstalled: true, isRunning: true, appRoot: appRoot, cliVersion: "1.6.1", apiServerVersion: "1.6.1")
        }
        containerSystem.mode = .cliCompatibility

        // Left over from a start while the CLI was stopped.
        containerSystem.startupError = ContainerSystem.SetupError.kernelInstallNotConfirmed

        try await containerSystem.start(appRoot: appRoot)

        #expect(!containerSystem.needsKernelConfirmation)
        #expect(containerSystem.status == .readOnly)
    }

    private func writeAPIServerPlist(in folder: URL) throws {
        let plist = folder.appending(path: "apiserver/apiserver.plist")

        try FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("<plist/>".utf8).write(to: plist)
    }

    @Test("Cancel with nothing starting")
    func cancelsNothingSafely() {
        let containerSystem = NeverFinishingSystem()

        containerSystem.cancelStart()

        #expect(containerSystem.status == .notStarted)
    }
}
