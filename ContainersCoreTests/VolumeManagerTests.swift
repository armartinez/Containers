//
//  VolumeManagerTests.swift
//  ContainersCoreTests
//
//  Created by Axel Martinez on 2026/02/08.
//

import ContainerizationEXT4
import ContainerizationError
import Foundation
import Testing

@testable import ContainersCore

@Suite("Volume manager", .serialized)
struct VolumeManagerTests {

    // MARK: - Setup Helper

    @MainActor
    private func setupTestSystem() async throws -> (URL, ContainerSystem) {
        let appRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-containers-\(UUID().uuidString)")

        let containerSystem = MockContainerSystem()

        try await containerSystem.start(appRoot: appRoot)

        return (appRoot, containerSystem)
    }

    // MARK: - List Volumes Tests

    @Test("Empty store lists no volumes")
    @MainActor
    func emptyStoreListsNoVolumes() async throws {
        let (_, containerSystem) = try await setupTestSystem()

        let volumeManager = VolumeManager(testSystem: containerSystem)
        let volumes = try await volumeManager.list()

        #expect(volumes.isEmpty)
    }

    // MARK: - Create Volume Tests

    @Test("Created volume is listed")
    @MainActor
    func createdVolumeIsListed() async throws {
        let (_, containerSystem) = try await setupTestSystem()

        let volumeName = "test-volume-\(UUID().uuidString)"
        let volumeManager = VolumeManager(testSystem: containerSystem)

        let volume = try await volumeManager.create(
            name: volumeName,
            labels: [],
            options: [],
            sizeInBytes: 1024 * 1024  // 1 MB
        )

        #expect(volume.name == volumeName)
        #expect(volume.driver == "local")
        #expect(volume.format == "ext4")
        #expect(volume.source.hasSuffix("volume.img"))
        #expect(volume.sizeInBytes == 1024 * 1024)

        let volumes = try await volumeManager.list()
        #expect(volumes.contains(where: { $0.name == volumeName }))
    }

    @Test("Default size when none given")
    @MainActor
    func createWithDefaultSize() async throws {
        let (_, containerSystem) = try await setupTestSystem()

        let volumeName = "test-volume-\(UUID().uuidString)"
        let volumeManager = VolumeManager(testSystem: containerSystem)

        let volume = try await volumeManager.create(
            name: volumeName,
            labels: [],
            options: [],
            sizeInBytes: nil
        )

        #expect(volume.source.hasSuffix("volume.img"))
        #expect(volume.sizeInBytes == VolumeStorage.defaultVolumeSizeBytes)

        let volumes = try await volumeManager.list()
        #expect(
            volumes.first(where: { $0.name == volumeName })?.sizeInBytes
                == VolumeStorage.defaultVolumeSizeBytes
        )
    }

    @Test("Size and journal come from the driver options, as the CLI reads them")
    @MainActor
    func createWithCLIDriverOptions() async throws {
        let (_, containerSystem) = try await setupTestSystem()

        let volumeManager = VolumeManager(testSystem: containerSystem)

        let volume = try await volumeManager.create(
            name: "test-volume-\(UUID().uuidString)",
            labels: [],
            options: [KeyValue(key: "size", value: "2m"), KeyValue(key: "journal", value: "writeback")],
            sizeInBytes: nil
        )

        #expect(volume.sizeInBytes == 2 * 1024 * 1024)
        #expect(volume.options["size"] == "2m")
        #expect(volume.options["journal"] == "writeback")
    }

    @Test("A size given directly is kept in the options, as the CLI keeps --size")
    @MainActor
    func createKeepsSizeInOptions() async throws {
        let (_, containerSystem) = try await setupTestSystem()

        let volumeManager = VolumeManager(testSystem: containerSystem)

        let volume = try await volumeManager.create(name: "test-volume-\(UUID().uuidString)", labels: [], options: [], sizeInBytes: 1024 * 1024)

        #expect(volume.options["size"] == "1048576")
    }

    @Test("Sizes and journals are read as the CLI reads them")
    func parsesCLIOptions() throws {
        #expect(try DefaultVolumeService.parseSize("512m") == 512 * 1024 * 1024)
        #expect(try DefaultVolumeService.parseSize("10GiB") == 10 * 1024 * 1024 * 1024)
        #expect(try DefaultVolumeService.parseSize("1048576") == 1024 * 1024)
        #expect(throws: VolumeError.self) { try DefaultVolumeService.parseSize("1k") }
        #expect(throws: VolumeError.self) { try DefaultVolumeService.parseSize("10x") }

        let journal = try DefaultVolumeService.parseJournal("journal:4m")
        #expect(journal.defaultMode == .journal)
        #expect(journal.size == 4 * 1024 * 1024)
        #expect(throws: VolumeError.self) { try DefaultVolumeService.parseJournal("fast") }
    }

    @Test("Invalid name throws")
    @MainActor
    func invalidNameThrows() async throws {
        let (_, containerSystem) = try await setupTestSystem()

        let volumeManager = VolumeManager(testSystem: containerSystem)

        await #expect(throws: VolumeError.self) {
            _ = try await volumeManager.create(
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
        let (_, containerSystem) = try await setupTestSystem()

        let volumeName = "test-volume-\(UUID().uuidString)"
        let volumeManager = VolumeManager(testSystem: containerSystem)

        _ = try await volumeManager.create(
            name: volumeName,
            labels: [],
            options: [],
            sizeInBytes: 1024 * 1024
        )

        await #expect(throws: VolumeError.self) {
            _ = try await volumeManager.create(
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
        let (_, containerSystem) = try await setupTestSystem()

        let volumeManager = VolumeManager(testSystem: containerSystem)

        try await volumeManager.delete(volumes: [])
    }

    @Test("Delete removes volume")
    @MainActor
    func deleteRemovesVolume() async throws {
        let (_, containerSystem) = try await setupTestSystem()

        let volumeName = "test-volume-\(UUID().uuidString)"
        let volumeManager = VolumeManager(testSystem: containerSystem)

        let volume = try await volumeManager.create(
            name: volumeName,
            labels: [],
            options: [],
            sizeInBytes: 1024 * 1024
        )

        try await volumeManager.delete(volumes: [volume])

        let volumes = try await volumeManager.list()
        #expect(!volumes.contains(where: { $0.name == volumeName }))
    }

    @Test("Delete removes the volume's reports")
    @MainActor
    func deleteRemovesVolumeReports() async throws {
        struct Failure: Error {}

        let (_, containerSystem) = try await setupTestSystem()

        let volumeName = "test-volume-\(UUID().uuidString)"
        let volumeManager = VolumeManager(testSystem: containerSystem)
        let reportManager = ReportManager(testSystem: containerSystem)

        let volume = try await volumeManager.create(
            name: volumeName,
            labels: [],
            options: [],
            sizeInBytes: 1024 * 1024
        )

        await reportManager.record(kind: .volume, name: volumeName, message: "The volume failed.", error: Failure())
        try await volumeManager.delete(volumes: [volume])

        #expect(reportManager.reports.isEmpty)
    }
}
