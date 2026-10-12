//
//  ContainerSystemTests.swift
//  ContainerSystemTests
//
//  Created by Axel Martinez on 2026/02/08.
//

import Foundation
import Testing

@testable import ContainerSystem

@Suite("Container system", .serialized)
struct ContainerSystemTests {

    @Test("Start system")
    @MainActor
    func startSystem() async throws {
        let testRuntime = MockContainerRuntime()
        let system = SystemManager(testRuntime: testRuntime)

        let appRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-containers-\(UUID().uuidString)")

        try await system.start(appRoot: appRoot)

        #expect(system.status == .running)

        try await system.stop()
    }

    @Test("Start twice")
    @MainActor
    func startTwice() async throws {
        let testRuntime = MockContainerRuntime()
        let system = SystemManager(testRuntime: testRuntime)

        let appRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-containers-\(UUID().uuidString)")

        try await system.start(appRoot: appRoot)
        #expect(system.status == .running)

        // Starting again should not cause error
        try await system.start(appRoot: appRoot)
        #expect(system.status == .running)

        try await system.stop()
    }

    @Test("Stop system")
    @MainActor
    func stopSystem() async throws {
        let testRuntime = MockContainerRuntime()
        let system = SystemManager(testRuntime: testRuntime)

        // Ensure system is started
        let appRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-containers-\(UUID().uuidString)")

        try await system.start(appRoot: appRoot)
        #expect(system.status == .running)

        // Stop the system
        try await system.stop()

        #expect(system.status == .notStarted)
    }
}
