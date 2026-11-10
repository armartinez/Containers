//
//  DefaultsStore.swift
//  Containers
//
//  Provides default configuration values for the container system.
//

import Foundation
import Synchronization

/// The container system's settings, by name, as its `config.toml` sets them.
///
/// The system reads them from its folder each time it starts; until then, they're the container CLI's defaults.
public enum DefaultsStore {
    /// Known configuration keys.
    public enum Key: String {
        case defaultInitImage = "defaultInitImage"
        case defaultBuilderImage = "defaultBuilderImage"
        case defaultKernelURL = "defaultKernelURL"
        case defaultKernelBinaryPath = "defaultKernelBinaryPath"
        case defaultKernelDigest = "defaultKernelDigest"
        case defaultDNSDomain = "defaultDNSDomain"
        case buildRosetta = "buildRosetta"
        case defaultContainerCPUs = "defaultContainerCPUs"
        case defaultContainerMemory = "defaultContainerMemory"
        case defaultBuildCPUs = "defaultBuildCPUs"
        case defaultBuildMemory = "defaultBuildMemory"
        case registryDomain = "registryDomain"
    }

    private static let current = Mutex(SystemConfiguration.defaults)

    /// The settings of the system's folder.
    public static var configuration: SystemConfiguration {
        get { current.withLock { $0 } }
        set { current.withLock { $0 = newValue } }
    }

    /// Get a required configuration value, or an empty string for one that isn't set.
    public static func get(key: Key) -> String {
        configuration.value(for: key) ?? ""
    }

    /// Get an optional configuration value. Returns nil if not set.
    public static func getOptional(key: Key) -> String? {
        configuration.value(for: key)
    }

    /// Get a boolean configuration value. Returns nil if not set.
    public static func getBool(key: Key) -> Bool? {
        configuration.value(for: key).map { $0 == "true" }
    }

    /// Get an integer configuration value. Returns nil if not set.
    public static func getInt(key: Key) -> Int? {
        configuration.value(for: key).flatMap(Int.init)
    }

    /// Get a UInt64 configuration value. Returns nil if not set.
    public static func getUInt64(key: Key) -> UInt64? {
        configuration.value(for: key).flatMap(UInt64.init)
    }
}
