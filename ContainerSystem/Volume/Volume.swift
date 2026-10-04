//
//  Volume.swift
//  Containers
//

import Foundation

/// Represents a container volume.
public struct Volume: Sendable, Codable, Identifiable, Equatable {
    public var name: String
    public var driver: String
    public var format: String
    public var source: String
    public var createdAt: Date
    public var labels: [String: String]
    public var options: [String: String]
    public var sizeInBytes: UInt64?

    public var id: String { name }

    /// Label key used to mark anonymous volumes.
    public static let anonymousLabel = "app.containers.resource.anonymous"

    /// Whether this volume is anonymous (auto-created, not explicitly named by user).
    public var isAnonymous: Bool {
        labels[Self.anonymousLabel] != nil
    }

    public init(
        name: String,
        driver: String = "local",
        format: String = "ext4",
        source: String = "",
        createdAt: Date = Date(),
        labels: [String: String] = [:],
        options: [String: String] = [:],
        sizeInBytes: UInt64? = nil
    ) {
        self.name = name
        self.driver = driver
        self.format = format
        self.source = source
        self.createdAt = createdAt
        self.labels = labels
        self.options = options
        self.sizeInBytes = sizeInBytes
    }
}

/// Errors related to volume operations.
public enum VolumeError: Error, LocalizedError {
    case volumeNotFound(String)
    case volumeAlreadyExists(String)
    case volumeInUse(String)
    case invalidVolumeName(String)
    case unsupportedDriver(String)
    case storageError(String)

    public var errorDescription: String? {
        switch self {
        case .volumeNotFound(let name):
            return "Volume not found: \(name)"
        case .volumeAlreadyExists(let name):
            return "Volume already exists: \(name)"
        case .volumeInUse(let name):
            return "Volume is in use: \(name)"
        case .invalidVolumeName(let msg):
            return msg
        case .unsupportedDriver(let driver):
            return "Unsupported volume driver: \(driver)"
        case .storageError(let msg):
            return "Volume storage error: \(msg)"
        }
    }
}

/// Utility functions for volume storage.
public struct VolumeStorage {
    /// Regex pattern for valid volume names.
    public static let volumeNamePattern = EntityName.pattern

    /// Default volume size: 512 GB.
    public static let defaultVolumeSizeBytes: UInt64 = 512 * 1024 * 1024 * 1024

    /// Validate a volume name.
    public static func isValidVolumeName(_ name: String) -> Bool {
        EntityName.isValid(name)
    }

    /// Generate a unique anonymous volume name.
    public static func anonymousVolumeName() -> String {
        UUID().uuidString.lowercased()
    }

    /// Generate a unique anonymous volume name (alias).
    public static func generateAnonymousVolumeName() -> String {
        anonymousVolumeName()
    }
}
