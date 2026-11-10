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
    public var creationDate: Date
    public var labels: [String: String]
    public var options: [String: String]
    public var sizeInBytes: UInt64?

    public var id: String { name }

    /// Label key used to mark anonymous volumes.
    /// The CLI's label, so each side recognizes the other's anonymous volumes.
    public static let anonymousLabel = "com.apple.container.resource.anonymous"

    /// Whether this volume is anonymous (auto-created, not explicitly named by user).
    public var isAnonymous: Bool {
        labels[Self.anonymousLabel] != nil
    }

    public init(
        name: String,
        driver: String = "local",
        format: String = "ext4",
        source: String = "",
        creationDate: Date = Date(),
        labels: [String: String] = [:],
        options: [String: String] = [:],
        sizeInBytes: UInt64? = nil
    ) {
        self.name = name
        self.driver = driver
        self.format = format
        self.source = source
        self.creationDate = creationDate
        self.labels = labels
        self.options = options
        self.sizeInBytes = sizeInBytes
    }
}

// Coded so a data folder can be shared with the CLI.
extension Volume {
    enum CodingKeys: String, CodingKey {
        case name
        case driver
        case format
        case source
        case creationDate
        case labels
        case options
        case sizeInBytes
        // What the CLI wrote before 1.0, which it still reads.
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.name = try container.decode(String.self, forKey: .name)
        self.driver = try container.decode(String.self, forKey: .driver)
        self.format = try container.decode(String.self, forKey: .format)
        self.source = try container.decode(String.self, forKey: .source)
        self.creationDate =
            try container.decodeIfPresent(Date.self, forKey: .creationDate)
            ?? container.decodeIfPresent(Date.self, forKey: .createdAt)
            ?? Date(timeIntervalSince1970: 0)
        self.labels = try container.decodeIfPresent([String: String].self, forKey: .labels) ?? [:]
        self.options = try container.decodeIfPresent([String: String].self, forKey: .options) ?? [:]
        self.sizeInBytes = try container.decodeIfPresent(UInt64.self, forKey: .sizeInBytes)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(name, forKey: .name)
        try container.encode(driver, forKey: .driver)
        try container.encode(format, forKey: .format)
        try container.encode(source, forKey: .source)
        try container.encode(creationDate, forKey: .creationDate)
        try container.encode(labels, forKey: .labels)
        try container.encode(options, forKey: .options)
        try container.encodeIfPresent(sizeInBytes, forKey: .sizeInBytes)
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
