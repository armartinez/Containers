//
//  DefaultsStore.swift
//  Containers
//
//  Provides default configuration values for the container system.
//

import Foundation

/// Provides access to default configuration values.
public enum DefaultsStore {

    /// Suite name for shared defaults.
    private static let suiteName = "app.containers.defaults"

    /// Known configuration keys.
    public enum Key: String {
        case defaultInitImage = "defaultInitImage"
        case defaultBuilderImage = "defaultBuilderImage"
        case defaultKernelURL = "defaultKernelURL"
        case defaultKernelBinaryPath = "defaultKernelBinaryPath"
        case defaultDNSDomain = "defaultDNSDomain"
        case buildRosetta = "buildRosetta"
        case defaultContainerCPUs = "defaultContainerCPUs"
        case defaultContainerMemory = "defaultContainerMemory"
        case defaultBuildCPUs = "defaultBuildCPUs"
        case defaultBuildMemory = "defaultBuildMemory"
        case defaultSubnet = "defaultSubnet"
        case registryDomain = "registryDomain"
    }

    /// Default values for each key.
    /// Image tags match the containerization package version pinned in Package.resolved.
    private static nonisolated(unsafe) let defaults: [Key: String] = [
        .defaultInitImage: "ghcr.io/apple/containerization/vminit:0.28.0",
        .defaultBuilderImage: "ghcr.io/apple/container-builder-shim/builder:0.12.0",
        .defaultKernelURL: "https://github.com/kata-containers/kata-containers/releases/download/3.26.0/kata-static-3.26.0-arm64.tar.zst",
        .defaultKernelBinaryPath: "opt/kata/share/kata-containers/vmlinux-6.18.5-177",
        .buildRosetta: "true",
        .defaultContainerCPUs: "2",
        .defaultContainerMemory: "2147483648",
        .defaultBuildCPUs: "4",
        .defaultBuildMemory: "4294967296",
        .defaultSubnet: "192.168.64.1/24",
    ]

    /// UserDefaults instance using the shared suite, falling back to standard.
    private static var userDefaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    /// Get a required configuration value. Uses UserDefaults override, then falls back to built-in defaults.
    public static func get(key: Key) -> String {
        if let override = userDefaults.string(forKey: key.rawValue), !override.isEmpty {
            return override
        }
        return defaults[key] ?? ""
    }

    /// Get an optional configuration value. Returns nil if not set.
    public static func getOptional(key: Key) -> String? {
        if let override = userDefaults.string(forKey: key.rawValue), !override.isEmpty {
            return override
        }
        return defaults[key]
    }

    /// Get a boolean configuration value. Returns nil if not set.
    public static func getBool(key: Key) -> Bool? {
        if userDefaults.object(forKey: key.rawValue) != nil {
            return userDefaults.bool(forKey: key.rawValue)
        }
        if let defaultValue = defaults[key] {
            return defaultValue.lowercased() == "true"
        }
        return nil
    }

    /// Get an integer configuration value. Returns nil if not set.
    public static func getInt(key: Key) -> Int? {
        if userDefaults.object(forKey: key.rawValue) != nil {
            return userDefaults.integer(forKey: key.rawValue)
        }
        if let defaultValue = defaults[key] {
            return Int(defaultValue)
        }
        return nil
    }

    /// Get a UInt64 configuration value. Returns nil if not set.
    public static func getUInt64(key: Key) -> UInt64? {
        if let str = userDefaults.string(forKey: key.rawValue), let val = UInt64(str) {
            return val
        }
        if let defaultValue = defaults[key] {
            return UInt64(defaultValue)
        }
        return nil
    }
}
