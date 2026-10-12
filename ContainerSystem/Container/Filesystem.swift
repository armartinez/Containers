//
//  Filesystem.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/04.
//

import Foundation
import SystemPackage

/// Represents a host filesystem attachment for a container.
public struct Filesystem: Sendable, Codable {

    /// Cache mode for block devices.
    public enum CacheMode: String, Sendable, Codable, Equatable {
        case on
        case off
        case auto
    }

    /// Sync mode for block devices.
    public enum SyncMode: String, Sendable, Codable, Equatable {
        case full
        case fsync
        case nosync
        case none = ""
    }

    /// The type of filesystem mount.
    public enum FilesystemType: Sendable, Codable, Equatable {
        case block(
            format: String,
            cache: CacheMode = .auto,
            sync: SyncMode = .none
        )
        case volume(
            name: String,
            format: String,
            cache: CacheMode = .auto,
            sync: SyncMode = .none
        )
        case virtiofs
        case tmpfs
    }

    public var type: FilesystemType
    public var source: String
    public var destination: String
    public var options: [String]

    public init(
        type: FilesystemType,
        source: String,
        destination: String,
        options: [String]
    ) {
        self.type = type
        self.source = source
        self.destination = destination
        self.options = options
    }

    // MARK: - Computed Properties

    public var isVirtiofs: Bool {
        if case .virtiofs = type { return true }
        return false
    }

    public var isBlock: Bool {
        if case .block = type { return true }
        return false
    }

    public var isVolume: Bool {
        if case .volume = type { return true }
        return false
    }

    public var isTmpfs: Bool {
        if case .tmpfs = type { return true }
        return false
    }

    public var volumeName: String? {
        if case .volume(let name, _, _, _) = type {
            return name
        }
        return nil
    }

    // MARK: - Factory Methods

    /// Create a block device filesystem mount.
    public static func block(
        format: String = "ext4",
        source: String,
        destination: String,
        cache: CacheMode = .auto,
        sync: SyncMode = .none,
        options: [String] = []
    ) -> Filesystem {
        Filesystem(
            type: .block(format: format, cache: cache, sync: sync),
            source: source,
            destination: destination,
            options: options
        )
    }

    /// Create a volume-based filesystem mount.
    public static func volume(
        name: String,
        format: String,
        source: String,
        destination: String,
        options: [String] = []
    ) -> Filesystem {
        Filesystem(
            type: .volume(name: name, format: format),
            source: source,
            destination: destination,
            options: options
        )
    }

    /// Create a virtiofs shared filesystem mount.
    public static func virtiofs(
        source: String,
        destination: String,
        options: [String] = []
    ) -> Filesystem {
        Filesystem(
            type: .virtiofs,
            source: source,
            destination: destination,
            options: options
        )
    }

    /// Create a tmpfs temporary filesystem mount.
    public static func tmpfs(destination: String, options: [String] = []) -> Filesystem {
        Filesystem(
            type: .tmpfs,
            source: "",
            destination: destination,
            options: options
        )
    }

    // MARK: - Cloning

    /// Creates a copy-on-write clone of the filesystem source.
    public func clone(to destination: URL) throws {
        let srcPath = FilePath(source)
        let dstPath = FilePath(destination.path)
        try FileManager.default.copyItem(
            atPath: srcPath.string,
            toPath: dstPath.string
        )
    }
}
