//
//  VolumeManagerTests.swift
//  ContainerSystemTests
//
//  Created by Axel Martinez on 2026/02/08.
//

import ContainerizationError
import Foundation
import Testing

@testable import ContainerSystem

@Suite("Volume manager", .serialized)
struct VolumeManagerTests {

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

    // MARK: - List Volumes Tests

    @Test("Empty store lists no volumes")
    @MainActor
    func emptyStoreListsNoVolumes() async throws {
        let (_, testRuntime) = try await setupTestSystem()

        let manager = VolumeManager(testRuntime: testRuntime)
        let volumes = try await manager.list()

        #expect(volumes.isEmpty)
    }

    // MARK: - Create Volume Tests

    @Test("Created volume is listed")
    @MainActor
    func createdVolumeIsListed() async throws {
        let (_, testRuntime) = try await setupTestSystem()

        let volumeName = "test-volume-\(UUID().uuidString)"
        let manager = VolumeManager(testRuntime: testRuntime)

        let volume = try await manager.create(
            name: volumeName,
            labels: [],
            options: [],
            sizeInBytes: 1024 * 1024  // 1 MB
        )

        #expect(volume.name == volumeName)
        #expect(volume.driver == "local")
        #expect(volume.format == "ext4")
        #expect(volume.source.hasSuffix("volume.ext4"))
        #expect(volume.sizeInBytes == 1024 * 1024)

        let volumes = try await manager.list()
        #expect(volumes.contains(where: { $0.name == volumeName }))
    }

    @Test("Default size when none given")
    @MainActor
    func createWithDefaultSize() async throws {
        let (_, testRuntime) = try await setupTestSystem()

        let volumeName = "test-volume-\(UUID().uuidString)"
        let manager = VolumeManager(testRuntime: testRuntime)

        let volume = try await manager.create(
            name: volumeName,
            labels: [],
            options: [],
            sizeInBytes: nil
        )

        #expect(volume.source.hasSuffix("volume.ext4"))
        #expect(volume.sizeInBytes == VolumeStorage.defaultVolumeSizeBytes)

        let volumes = try await manager.list()
        #expect(
            volumes.first(where: { $0.name == volumeName })?.sizeInBytes
                == VolumeStorage.defaultVolumeSizeBytes
        )
    }

    @Test("Invalid name throws")
    @MainActor
    func invalidNameThrows() async throws {
        let (_, testRuntime) = try await setupTestSystem()

        let manager = VolumeManager(testRuntime: testRuntime)

        await #expect(throws: VolumeError.self) {
            _ = try await manager.create(
                name: "invalid name!",
                labels: [],
                options: [],
                sizeInBytes: nil
            )
        }
    }

    @Test("Duplicate name throws")
    @MainActor
    func duplicateNameThrows() async throws {
        let (_, testRuntime) = try await setupTestSystem()

        let volumeName = "test-volume-\(UUID().uuidString)"
        let manager = VolumeManager(testRuntime: testRuntime)

        _ = try await manager.create(
            name: volumeName,
            labels: [],
            options: [],
            sizeInBytes: 1024 * 1024
        )

        await #expect(throws: VolumeError.self) {
            _ = try await manager.create(
                name: volumeName,
                labels: [],
                options: [],
                sizeInBytes: 1024 * 1024
            )
        }
    }

    // MARK: - Delete Volume Tests

    @Test("Delete empty list")
    @MainActor
    func deleteEmptyList() async throws {
        let (_, testRuntime) = try await setupTestSystem()

        let manager = VolumeManager(testRuntime: testRuntime)

        try await manager.delete(volumes: [])
    }

    @Test("Delete removes volume")
    @MainActor
    func deleteRemovesVolume() async throws {
        let (_, testRuntime) = try await setupTestSystem()

        let volumeName = "test-volume-\(UUID().uuidString)"
        let manager = VolumeManager(testRuntime: testRuntime)

        let volume = try await manager.create(
            name: volumeName,
            labels: [],
            options: [],
            sizeInBytes: 1024 * 1024
        )

        try await manager.delete(volumes: [volume])

        let volumes = try await manager.list()
        #expect(!volumes.contains(where: { $0.name == volumeName }))
    }
}
