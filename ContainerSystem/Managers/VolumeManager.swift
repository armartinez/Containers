//
//  VolumeManager.swift
//  Containers
//
//  Manager for volume operations
//
//  Created by Axel Martinez on 2026/02/04.
//

import ContainerizationEXT4
import ContainerizationError
import Foundation
import Logging
import Observation
import SystemPackage

/// Manages volume operations.
/// Create instances via public init() - automatically references shared runtime.
@Observable
@MainActor
public final class VolumeManager {

    /// Internal runtime reference (hidden from UI)
    let runtime: ContainerRuntime

    private let logger: Logger

    // Storage constants
    private static let blockFile = "volume.ext4"

    /// Public initializer - creates instance referencing shared runtime
    public init() {
        self.runtime = ContainerRuntime.shared

        var logger = Logger(label: "app.containers.manager.volume")
        logger.logLevel = .info

        self.logger = logger
    }

    #if DEBUG
    /// Internal initializer for testing - allows injection of test runtime
    init(testRuntime: ContainerRuntime) {
        self.runtime = testRuntime

        var logger = Logger(label: "app.containers.manager.volumes.test")
        logger.logLevel = .debug

        self.logger = logger
    }
    #endif

    // MARK: - Public API

    @discardableResult
    public func create(
        name: String,
        labels: [KeyValue],
        options: [KeyValue],
        sizeInBytes: UInt64?
    ) async throws -> Volume {
        guard VolumeStorage.isValidVolumeName(name) else {
            throw VolumeError.invalidVolumeName("invalid volume name '\(name)': must match \(VolumeStorage.volumeNamePattern)")
        }

        let store = try await getStore()
        let existingVolumes = try await store.list()

        if existingVolumes.contains(where: { $0.name == name }) {
            throw VolumeError.volumeAlreadyExists(name)
        }

        let volumesRoot = try getVolumesRoot()
        let volumeDir = volumesRoot.appendingPathComponent(name)

        try FileManager.default.createDirectory(at: volumeDir, withIntermediateDirectories: true)

        let blockPath = volumeDir.appendingPathComponent(Self.blockFile).path
        let filesystemSize = sizeInBytes ?? VolumeStorage.defaultVolumeSizeBytes
        let labelsDict = labels.reduce(into: [String: String]()) {
            $0[$1.key] = $1.value
        }
        let optionsDict = options.reduce(into: [String: String]()) {
            $0[$1.key] = $1.value
        }

        do {
            let formatter = try EXT4.Formatter(
                FilePath(blockPath),
                blockSize: 4096,
                minDiskSize: filesystemSize
            )

            try formatter.close()
        } catch {
            // Clean up the directory on failure
            try? FileManager.default.removeItem(at: volumeDir)

            throw VolumeError.storageError("failed to create volume image: \(error)")
        }

        let volume = Volume(
            name: name,
            driver: "local",
            format: "ext4",
            source: blockPath,
            labels: labelsDict,
            options: optionsDict,
            sizeInBytes: filesystemSize
        )

        try await store.create(volume)

        logger.info("Created volume: \(name)")

        return volume
    }

    public func list() async throws -> [Volume] {
        let store = try await getStore()

        return try await store.list()
    }

    public func summaries() async throws -> [VolumeSummary] {
        let store = try await getStore()
        let service = try await runtime.getContainersService()
        let usedVolumeNames = Set(await service.list().flatMap(\.volumeNames))

        return try await store.list().map { volume in
            VolumeSummary(volume: volume, isInUse: usedVolumeNames.contains(volume.name))
        }
    }

    public func delete(volumes: [Volume]) async throws {
        let store = try await getStore()
        let service = try await runtime.getContainersService()
        let containers = await service.list()

        var failed: [(String, Error)] = []
        var deleted: [String] = []

        for volume in volumes {
            do {
                // Check if volume is in use by any container
                let isInUse = containers.contains { container in
                    container.configuration.mounts.contains { mount in
                        mount.isVolume && mount.volumeName == volume.name
                    }
                }

                if isInUse {
                    throw VolumeError.volumeInUse(volume.name)
                }

                try await store.delete(volume.name)

                let volumesRoot = try getVolumesRoot()
                let volumeDir = volumesRoot.appendingPathComponent(volume.name)

                if FileManager.default.fileExists(atPath: volumeDir.path) {
                    try FileManager.default.removeItem(at: volumeDir)
                }

                deleted.append(volume.name)
                logger.info("Deleted volume: \(volume.name)")
            } catch {
                logger.error("Failed to delete volume \(volume.name): \(error)")
                failed.append((volume.name, error))
            }
        }

        await ReportManager(runtime: runtime).remove(named: deleted, ofKind: [.volume])

        if !failed.isEmpty {
            throw ContainerizationError(
                .internalError,
                message:
                    "Failed to delete one or more volumes: \n\(failed.map({"\($0.0): \($0.1)"}).joined(separator: "\n"))"
            )
        }
    }

    // MARK: - Private Helpers

    private func getVolumesRoot() throws -> URL {
        let appRoot = try runtime.getAppRoot()
        let volumesRoot = appRoot.appendingPathComponent("volumes")

        try FileManager.default.createDirectory(at: volumesRoot, withIntermediateDirectories: true)

        return volumesRoot
    }

    private func getStore() async throws -> FilesystemEntityStore<Volume> {
        let volumesRoot = try getVolumesRoot()

        return try FilesystemEntityStore<Volume>(path: volumesRoot, type: "volumes", log: logger)
    }
}

extension VolumeManager {
    /// The volume of that name, created if it does not exist yet. An empty
    /// name gets a fresh anonymous one.
    public func volume(named name: String, among existing: [Volume]) async throws -> Volume {
        if !name.isEmpty, let match = existing.first(where: { $0.name == name }) {
            return match
        }

        var volumeName = name
        var labels: [KeyValue] = []

        if volumeName.isEmpty {
            volumeName = VolumeStorage.generateAnonymousVolumeName()
            labels.append(.init(key: Volume.anonymousLabel))
        }

        return try await create(name: volumeName, labels: labels, options: [], sizeInBytes: nil)
    }
}
