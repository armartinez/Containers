//
//  VolumeManager.swift
//  Containers
//
//  Manager for volume operations
//
//  Created by Axel Martinez on 2026/02/04.
//

import ContainerizationError
import Foundation
import Logging
import Observation

/// A manager that creates, lists and deletes volumes.
///
/// Each volume is an ext4 disk image in the container system's storage folder.
@Observable
@MainActor
public final class VolumeManager {

    let containerSystem: ContainerSystem

    private let logger: Logger

    /// The time the container CLI last made or removed a volume, while the system is read-only.
    ///
    /// Observe this property to refresh a list of volumes.
    public var lastSharedVolumeChange: Date {
        containerSystem.lastSharedVolumeChange
    }

    /// Creates a manager for the shared container system.
    public init() {
        self.containerSystem = ContainerSystem.shared

        var logger = Logger(label: "app.containers.manager.volume")
        logger.logLevel = .info

        self.logger = logger
    }

    #if DEBUG
    /// Creates a manager over the given container system, so tests can use one of their own.
    init(testSystem: ContainerSystem) {
        self.containerSystem = testSystem

        var logger = Logger(label: "app.containers.manager.volumes.test")
        logger.logLevel = .debug

        self.logger = logger
    }
    #endif

    // MARK: - Public API

    /// Creates a volume.
    ///
    /// - Parameters:
    ///   - name: The volume's name, which must be unique and use only valid characters.
    ///   - labels: Labels to add to the volume.
    ///   - options: Driver options for the volume.
    ///   - sizeInBytes: The volume's size, or `nil` for the default size.
    /// - Returns: The new volume.
    /// - Throws: ``ContainerCLIError/apiServerRunning`` while the system is read-only, or an error if the name isn't valid, a volume with that name exists, or the
    ///   volume can't be created.
    @discardableResult
    public func create(
        name: String,
        labels: [KeyValue],
        options: [KeyValue],
        sizeInBytes: UInt64?
    ) async throws -> Volume {
        let volume = try await containerSystem.volumeService.create(
            name: name,
            labels: labels.reduce(into: [:]) { $0[$1.key] = $1.value },
            options: options.reduce(into: [:]) { $0[$1.key] = $1.value },
            sizeInBytes: sizeInBytes
        )

        logger.info("Created volume: \(name)")

        return volume
    }

    /// Returns every volume.
    public func list() async throws -> [Volume] {
        try await containerSystem.volumeService.list()
    }

    /// Returns every volume, with whether a container uses it.
    public func summaries() async throws -> [VolumeSummary] {
        let service = try containerSystem.containerService
        let usedVolumeNames = Set(await service.list().flatMap(\.volumeNames))

        return try await containerSystem.volumeService.list().map { volume in
            VolumeSummary(volume: volume, isInUse: usedVolumeNames.contains(volume.name))
        }
    }

    /// Deletes volumes, along with their data and any reports about them.
    ///
    /// A volume that a container uses isn't deleted.
    ///
    /// - Parameter volumes: The volumes to delete.
    /// - Throws: ``ContainerCLIError/apiServerRunning`` while the system is read-only, or an error that lists each volume that couldn't be deleted.
    public func delete(volumes: [Volume]) async throws {
        let volumeService = try containerSystem.volumeService
        let containerService = try containerSystem.containerService

        var failed: [(String, Error)] = []
        var deleted: [String] = []

        for volume in volumes {
            let name = volume.name

            do {
                // No container can be created between the check and the delete.
                try await containerService.withContainerList { configurations in
                    let containerIDs = configurations.filter { $0.mounts.contains { $0.isVolume && $0.volumeName == name } }.map(\.id)

                    try await volumeService.delete(named: name, inUseBy: containerIDs)
                }

                deleted.append(name)
                logger.info("Deleted volume: \(name)")
            } catch ContainerCLIError.apiServerRunning {
                // Refused for the whole system, so for every one of them.
                throw ContainerCLIError.apiServerRunning
            } catch {
                logger.error("Failed to delete volume \(name): \(error)")
                failed.append((name, error))
            }
        }

        try await containerSystem.reportService.delete(named: deleted, ofKind: [.volume])

        if !failed.isEmpty {
            throw ContainerizationError(
                .internalError,
                message:
                    "Failed to delete one or more volumes: \n\(failed.map({"\($0.0): \($0.1)"}).joined(separator: "\n"))"
            )
        }
    }

}

extension VolumeManager {
    /// Returns the volume with a name, creating it if it doesn't exist yet.
    ///
    /// - Parameters:
    ///   - name: The volume's name. An empty name creates a new anonymous volume.
    ///   - existing: The volumes that exist, to look the name up in.
    /// - Returns: The existing or new volume.
    /// - Throws: An error if the volume can't be created.
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
