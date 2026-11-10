//
//  DefaultVolumeService.swift
//  Containers
//
//  The volumes containers mount, as ext4 disk images in the system's folder.
//
//  Created by Axel Martinez on 2026/11/06.
//

import ContainerizationEXT4
import Foundation
import Logging
import SystemPackage

/// The volumes kept in the system's folder, each an ext4 disk image beside its entry in the store.
struct DefaultVolumeService: VolumeService {
    private static let blockFile = "volume.img"

    let volumesRoot: URL
    let log: Logger

    init(appRoot: URL, log: Logger) {
        self.volumesRoot = appRoot.appendingPathComponent("volumes")
        self.log = log
    }

    /// Creates a volume, formatting its disk image.
    ///
    /// - Parameters:
    ///   - name: The volume's name, which must be unique and use only valid characters.
    ///   - labels: Labels to add to the volume.
    ///   - options: Driver options for the volume, such as its `size` and `journal`.
    ///   - sizeInBytes: The volume's size, or `nil` for the one in `options`, or the default size.
    /// - Returns: The new volume.
    /// - Throws: An error if the name isn't valid, a volume with that name exists, or the volume can't be created.
    func create(name: String, labels: [String: String], options: [String: String], sizeInBytes: UInt64?) async throws -> Volume {
        guard VolumeStorage.isValidVolumeName(name) else {
            throw VolumeError.invalidVolumeName("invalid volume name '\(name)': must match \(VolumeStorage.volumeNamePattern)")
        }

        let store = try store()

        if try await store.list().contains(where: { $0.name == name }) {
            throw VolumeError.volumeAlreadyExists(name)
        }

        let volumeDirectory = volumesRoot.appendingPathComponent(name)

        try FileManager.default.createDirectory(at: volumeDirectory, withIntermediateDirectories: true)

        let blockPath = volumeDirectory.appendingPathComponent(Self.blockFile).path
        var options = options

        // Kept in the options, which is where the size is read back from.
        if let sizeInBytes {
            options["size"] = "\(sizeInBytes)"
        }

        let filesystemSize: UInt64
        let journal: EXT4.JournalConfig?

        do {
            filesystemSize = try options["size"].map(Self.parseSize) ?? VolumeStorage.defaultVolumeSizeBytes
            journal = try options["journal"].map(Self.parseJournal)
        } catch {
            try? FileManager.default.removeItem(at: volumeDirectory)

            throw error
        }

        do {
            let formatter = try EXT4.Formatter(FilePath(blockPath), blockSize: 4096, minDiskSize: filesystemSize, journal: journal)

            try formatter.close()
        } catch {
            try? FileManager.default.removeItem(at: volumeDirectory)

            throw VolumeError.storageError("failed to create volume image: \(error)")
        }

        let volume = Volume(
            name: name,
            driver: "local",
            format: "ext4",
            source: blockPath,
            labels: labels,
            options: options,
            sizeInBytes: filesystemSize
        )

        try await store.create(volume)

        return volume
    }

    /// Deletes a volume and its disk image, unless a container uses it.
    ///
    /// - Parameters:
    ///   - name: The volume to delete.
    ///   - containerIDs: The containers configured to mount the volume, running or not.
    /// - Throws: An error if a container uses the volume, or it can't be deleted.
    func delete(named name: String, inUseBy containerIDs: [String]) async throws {
        guard containerIDs.isEmpty else {
            throw VolumeError.volumeInUse(name)
        }

        try await store().delete(name)

        let volumeDirectory = volumesRoot.appendingPathComponent(name)

        if FileManager.default.fileExists(atPath: volumeDirectory.path) {
            try FileManager.default.removeItem(at: volumeDirectory)
        }
    }

    // MARK: - Driver Options

    /// Reads a volume's size, which must be at least 1 MiB.
    static func parseSize(_ value: String) throws -> UInt64 {
        let bytes = try parseBytes(value)

        guard bytes >= 1024 * 1024 else {
            throw VolumeError.storageError("volume size too small: minimum 1MiB")
        }

        return bytes
    }

    /// Reads a journal: `mode` or `mode:size`, with the mode `writeback`, `ordered` or `journal`.
    static func parseJournal(_ value: String) throws -> EXT4.JournalConfig {
        let parts = value.split(separator: ":", maxSplits: 1)
        let mode: EXT4.JournalConfig.JournalMode

        switch parts.first.map(String.init) {
        case "writeback": mode = .writeback
        case "ordered": mode = .ordered
        case "journal": mode = .journal
        default:
            throw VolumeError.storageError("invalid journal mode '\(parts.first ?? "")': must be writeback, ordered, or journal")
        }

        let size = try parts.count > 1 ? parseBytes(String(parts[1])) : nil

        return EXT4.JournalConfig(size: size, defaultMode: mode)
    }

    private static func parseBytes(_ value: String) throws -> UInt64 {
        guard let bytes = ByteSize.bytes(from: value) else {
            throw VolumeError.storageError("invalid volume size '\(value)'")
        }

        return bytes
    }
}
