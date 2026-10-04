//
//  ContainerManagerTests.swift
//  ContainerSystemTests
//
//  Created by Axel Martinez on 2026/02/08.
//

import ContainerizationError
import Foundation
import Testing

@testable import ContainerSystem

@Suite("Container manager")
struct ContainerManagerTests {

    // MARK: - Setup Helper

    @MainActor
    private func setupTestSystem() async throws -> (URL, ContainerRuntime) {
        let appRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-containers-\(UUID().uuidString)")

        let testRuntime = MockContainerRuntime()
        let system = SystemManager(testRuntime: testRuntime)
        try await system.start(appRoot: appRoot)

        return (appRoot, testRuntime)
    }

    // MARK: - List Containers Tests

    @Test("Empty store lists no containers")
    @MainActor
    func emptyStoreListsNoContainers() async throws {
        let (_, testRuntime) = try await setupTestSystem()

        let manager = ContainerManager(testRuntime: testRuntime)
        let containers = try await manager.list()

        #expect(containers.isEmpty)
    }

    // MARK: - Get Container Tests

    @Test("Get missing container throws")
    @MainActor
    func getMissingContainerThrows() async throws {
        let (_, testRuntime) = try await setupTestSystem()

        let manager = ContainerManager(testRuntime: testRuntime)
        do {
            _ = try await manager.get(id: "nonexistent-container-id")
            Issue.record("Expected ContainerizationError")
        } catch let error as ContainerizationError {
            #expect(error.code == .notFound)
        }
    }
}
