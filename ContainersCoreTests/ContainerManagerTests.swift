//
//  ContainerManagerTests.swift
//  ContainersCoreTests
//
//  Created by Axel Martinez on 2026/02/08.
//

import ContainerizationError
import Foundation
import Testing

@testable import ContainersCore

@Suite("Container manager")
struct ContainerManagerTests {

    // MARK: - Setup Helper

    @MainActor
    private func setupTestSystem() async throws -> (URL, ContainerSystem) {
        let appRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-containers-\(UUID().uuidString)")

        let containerSystem = MockContainerSystem()
        try await containerSystem.start(appRoot: appRoot)

        return (appRoot, containerSystem)
    }

    // MARK: - List Containers Tests

    @Test("Empty store lists no containers")
    @MainActor
    func emptyStoreListsNoContainers() async throws {
        let (_, containerSystem) = try await setupTestSystem()

        let containerManager = ContainerManager(testSystem: containerSystem)
        let containers = try await containerManager.list()

        #expect(containers.isEmpty)
    }

    // MARK: - Get Container Tests

    @Test("Get missing container throws")
    @MainActor
    func getMissingContainerThrows() async throws {
        let (_, containerSystem) = try await setupTestSystem()

        let containerManager = ContainerManager(testSystem: containerSystem)
        do {
            _ = try await containerManager.get(id: "nonexistent-container-id")
            Issue.record("Expected ContainerizationError")
        } catch let error as ContainerizationError {
            #expect(error.code == .notFound)
        }
    }
}
