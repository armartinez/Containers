//
//  KeyValue.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import Foundation

/// A mutable key-value pair model for SwiftUI forms and lists
///
/// This type bridges between Swift's native Dictionary type and SwiftUI's requirements
/// for Identifiable, mutable collections in forms. It maintains insertion order and
/// provides utilities for parsing container configurations.
public struct KeyValue: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var key: String
    public var value: String

    /// Creates a new key-value pair
    /// - Parameters:
    ///   - key: The key string
    ///   - value: The value string
    ///   - id: Optional UUID for identification (generates new UUID if not provided)
    public init(key: String = "", value: String = "", id: UUID = UUID()) {
        self.id = id
        self.key = key
        self.value = value
    }

    /// Creates key-value pairs from container environment variables
    /// - Parameter snapshot: Container snapshot containing environment variables
    /// - Returns: Array of key-value pairs parsed from "KEY=VALUE" format
    public static func fromEnvironment(_ snapshot: ContainerSnapshot)
        -> [KeyValue]
    {
        snapshot.configuration.initProcess.environment
            .compactMap { Self.parse($0) }
    }

    /// Creates key-value pairs from container port mappings
    /// - Parameter snapshot: Container snapshot containing published ports
    /// - Returns: Array of key-value pairs with host and container port information
    public static func fromPorts(_ snapshot: ContainerSnapshot) -> [KeyValue] {
        snapshot.configuration.publishedPorts.map { port in
            let host = "\(port.hostAddress):\(port.hostPort)"
            let container =
                "\(port.containerPort)[\(port.proto.rawValue.uppercased())]"
            return KeyValue(key: host, value: container)
        }
    }

    /// Parses a key-value string in "KEY=VALUE" format
    /// - Parameter string: String to parse
    /// - Returns: KeyValue if parsing succeeds, nil if string is invalid
    public static func parse(_ string: String) -> KeyValue? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { return nil }

        return KeyValue(key: String(parts[0]), value: String(parts[1]))
    }

    /// Creates key-value pairs from a dictionary
    /// - Parameter dictionary: Dictionary to convert
    /// - Returns: Array of key-value pairs (order not guaranteed)
    public static func from(dictionary: [String: String]) -> [KeyValue] {
        dictionary.map { KeyValue(key: $0.key, value: $0.value) }
    }
}

// MARK: - Array Extensions
extension Array where Element == KeyValue {
    /// Converts the array of key-value pairs to a dictionary
    /// - Returns: Dictionary representation (later values override earlier ones for duplicate keys)
    var asDictionary: [String: String] {
        Dictionary(
            map { ($0.key, $0.value) },
            uniquingKeysWith: { _, last in last }
        )
    }

    /// Converts the array to environment variable format strings
    /// - Returns: Array of "KEY=VALUE" formatted strings
    var asEnvironmentStrings: [String] {
        map { "\($0.key)=\($0.value)" }
    }
}
