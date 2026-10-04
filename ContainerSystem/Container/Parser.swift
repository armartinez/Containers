//
//  Parser.swift
//  Containers
//
//  Utility for parsing container configuration values.
//

import ContainerizationExtras
import ContainerizationOCI
import Foundation

/// Utility for parsing container configuration values.
public enum Parser {

    /// Create a Platform from os and arch strings.
    public static func platform(os: String, arch: String) -> Platform {
        var variant: String? = nil
        if arch == "arm64" {
            variant = "v8"
        }
        return Platform(arch: arch, os: os, variant: variant)
    }

    /// Parse a platform string (e.g. "linux/arm64") into a Platform.
    public static func platform(
        from platformString: String
    ) throws -> Platform {
        let parts = platformString.split(separator: "/")
        guard parts.count >= 2 else {
            return platform(os: "linux", arch: platformString)
        }
        let os = String(parts[0])
        let arch = String(parts[1])
        let variant = parts.count > 2 ? String(parts[2]) : nil
        return Platform(arch: arch, os: os, variant: variant)
    }

    /// Merge environment variables from image config, env files, and explicit envs.
    public static func allEnv(
        imageEnvs: [String],
        envFiles: [String],
        envs: [String]
    ) throws -> [String] {
        var result = imageEnvs

        // Parse env files
        for envFile in envFiles {
            let contents = try String(contentsOfFile: envFile, encoding: .utf8)
            let lines = contents.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                    result.append(trimmed)
                }
            }
        }

        // Add explicit environment variables (these override earlier ones)
        result.append(contentsOf: envs)

        return result
    }

    /// Parse user specification into a ProcessConfiguration.User and supplemental groups.
    public static func user(
        user: String?,
        uid: UInt32?,
        gid: UInt32?,
        defaultUser: ProcessConfiguration.User
    ) -> (ProcessConfiguration.User, [UInt32]) {
        if let user = user, !user.isEmpty {
            return (.raw(userString: user), [])
        }

        if let uidValue = uid {
            let gidValue = gid ?? uidValue
            return (.id(uid: uidValue, gid: gidValue), [])
        }

        return (defaultUser, [])
    }

    // MARK: - Mount Parsing

    /// Parse a mount string into a Filesystem.
    /// Supports formats:
    /// - Short: `source:destination[:options]`
    /// - Named: `type=volume,source=name,destination=/path,volume-opt=key=value`
    public static func mount(from spec: String) throws -> Filesystem {
        // Named format: key=value pairs separated by commas
        if spec.contains("=") && !spec.hasPrefix("/") {
            return try parseNamedMount(spec)
        }

        // Short format: source:destination[:options]
        let parts = spec.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else {
            throw ParserError.invalidMountSpec("invalid mount spec: \(spec)")
        }

        let source = parts[0]
        let destination = parts[1]
        let options =
            parts.count > 2
            ? parts[2].split(separator: ",").map(String.init) : []

        // Determine if this is a volume or bind mount
        if source.hasPrefix("/") || source.hasPrefix(".")
            || source.hasPrefix("~")
        {
            // Bind mount (virtiofs)
            return Filesystem(
                type: .virtiofs,
                source: source,
                destination: destination,
                options: options
            )
        }

        // Named volume
        return Filesystem.volume(
            name: source,
            format: "ext4",
            source: "",
            destination: destination,
            options: options
        )
    }

    private static func parseNamedMount(_ spec: String) throws -> Filesystem {
        var pairs: [String: String] = [:]
        var volumeOpts: [String] = []

        for component in spec.split(separator: ",") {
            let kv = component.split(separator: "=", maxSplits: 1).map(
                String.init
            )
            guard kv.count == 2 else { continue }

            if kv[0] == "volume-opt" {
                volumeOpts.append(kv[1])
            } else {
                pairs[kv[0]] = kv[1]
            }
        }

        let destination =
            pairs["destination"] ?? pairs["dst"] ?? pairs["target"] ?? "/"
        let source = pairs["source"] ?? pairs["src"] ?? ""
        let typeStr = pairs["type"] ?? "volume"

        switch typeStr {
        case "volume":
            let name =
                source.isEmpty
                ? VolumeStorage.generateAnonymousVolumeName() : source
            return Filesystem.volume(
                name: name,
                format: "ext4",
                source: "",
                destination: destination,
                options: volumeOpts
            )
        case "bind":
            return Filesystem(
                type: .virtiofs,
                source: source,
                destination: destination,
                options: volumeOpts
            )
        case "tmpfs":
            return Filesystem(
                type: .tmpfs,
                source: "",
                destination: destination,
                options: volumeOpts
            )
        default:
            throw ParserError.invalidMountSpec(
                "unsupported mount type: \(typeStr)"
            )
        }
    }

    // MARK: - Port Parsing

    /// Parse a port specification string into a PublishPort.
    /// Supports Docker-compatible formats:
    /// - `containerPort` (e.g. "80")
    /// - `hostPort:containerPort` (e.g. "8080:80")
    /// - `hostPort:containerPort/protocol` (e.g. "8080:80/tcp")
    /// - `hostIP:hostPort:containerPort` (e.g. "127.0.0.1:8080:80")
    /// - `hostIP:hostPort:containerPort/protocol` (e.g. "0.0.0.0:8080:80/udp")
    /// - Port ranges: `hostStart-hostEnd:containerStart-containerEnd`
    public static func port(from spec: String) throws -> PublishPort {
        var spec = spec

        // Extract protocol suffix
        var proto = PublishProtocol.tcp
        if let slashIdx = spec.lastIndex(of: "/") {
            let protoStr = String(spec[spec.index(after: slashIdx)...])
            proto = PublishProtocol(protoStr)
            spec = String(spec[..<slashIdx])
        }

        let parts = spec.split(separator: ":").map(String.init)

        switch parts.count {
        case 1:
            // containerPort only
            let (containerStart, count) = try parsePortRange(parts[0])
            return PublishPort(
                hostPort: containerStart,
                containerPort: containerStart,
                proto: proto,
                count: count
            )

        case 2:
            // hostPort:containerPort
            let (hostStart, hostCount) = try parsePortRange(parts[0])
            let (containerStart, containerCount) = try parsePortRange(parts[1])
            let count = max(hostCount, containerCount)
            return PublishPort(
                hostPort: hostStart,
                containerPort: containerStart,
                proto: proto,
                count: count
            )

        case 3:
            // hostIP:hostPort:containerPort
            let hostAddress = try IPAddress(parts[0])
            let (hostStart, hostCount) = try parsePortRange(parts[1])
            let (containerStart, containerCount) = try parsePortRange(parts[2])
            let count = max(hostCount, containerCount)
            return PublishPort(
                hostAddress: hostAddress,
                hostPort: hostStart,
                containerPort: containerStart,
                proto: proto,
                count: count
            )

        default:
            throw ParserError.invalidPortSpec(
                "invalid port specification: \(spec)"
            )
        }
    }

    private static func parsePortRange(_ range: String) throws -> (
        start: UInt16, count: UInt16
    ) {
        if range.contains("-") {
            let bounds = range.split(separator: "-").map(String.init)
            guard bounds.count == 2,
                let start = UInt16(bounds[0]),
                let end = UInt16(bounds[1]),
                end >= start
            else {
                throw ParserError.invalidPortSpec(
                    "invalid port range: \(range)"
                )
            }
            return (start, end - start + 1)
        }

        guard let port = UInt16(range) else {
            throw ParserError.invalidPortSpec("invalid port number: \(range)")
        }
        return (port, 1)
    }

    // MARK: - Memory Parsing

    /// Parse a human-readable memory string into bytes.
    /// Supports: "512m", "1g", "1024k", "1073741824", "2.5g", "64mib"
    public static func memoryInBytes(from spec: String) throws -> UInt64 {
        let trimmed = spec.trimmingCharacters(in: .whitespaces).lowercased()

        guard !trimmed.isEmpty else {
            throw ParserError.invalidMemorySpec("empty memory specification")
        }

        // Pure numeric value (already in bytes)
        if let bytes = UInt64(trimmed) {
            return bytes
        }

        // Extract numeric part and suffix
        let suffixChars: Set<Character> = [
            "k", "m", "g", "t", "p", "b", "i",
        ]
        var numericPart = trimmed
        var suffix = ""

        while let last = numericPart.last, suffixChars.contains(last) {
            suffix = String(last) + suffix
            numericPart.removeLast()
        }

        guard let value = Double(numericPart), value > 0 else {
            throw ParserError.invalidMemorySpec(
                "invalid numeric value in: \(spec)"
            )
        }

        // Every unit is a binary one, so "m", "mb" and "mib" all name the
        // same size, the way the container CLI reads them.
        let multiplier: Double
        switch suffix {
        case "k", "kb", "kib":
            multiplier = 1024
        case "m", "mb", "mib":
            multiplier = 1024 * 1024
        case "g", "gb", "gib":
            multiplier = 1024 * 1024 * 1024
        case "t", "tb", "tib":
            multiplier = 1024 * 1024 * 1024 * 1024
        case "p", "pb", "pib":
            multiplier = 1024 * 1024 * 1024 * 1024 * 1024
        case "b", "":
            multiplier = 1
        default:
            throw ParserError.invalidMemorySpec(
                "unknown memory suffix: \(suffix)"
            )
        }

        let bytes = value * multiplier

        guard bytes < Double(UInt64.max) else {
            throw ParserError.invalidMemorySpec(
                "memory value out of range: \(spec)"
            )
        }

        return UInt64(bytes)
    }

    // MARK: - Rlimit Parsing

    /// Parse an rlimit specification: `type=soft:hard` or `type=value`
    public static func rlimit(from spec: String) throws
        -> ProcessConfiguration.Rlimit
    {
        let parts = spec.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            throw ParserError.invalidRlimitSpec(
                "invalid rlimit format: \(spec)"
            )
        }

        let limitType = parts[0]
        let values = parts[1].split(separator: ":").map(String.init)

        guard let soft = UInt64(values[0]) else {
            throw ParserError.invalidRlimitSpec(
                "invalid soft limit: \(values[0])"
            )
        }

        let hard: UInt64
        if values.count > 1 {
            guard let h = UInt64(values[1]) else {
                throw ParserError.invalidRlimitSpec(
                    "invalid hard limit: \(values[1])"
                )
            }
            hard = h
        } else {
            hard = soft
        }

        return ProcessConfiguration.Rlimit(
            limit: limitType,
            soft: soft,
            hard: hard
        )
    }
}

// MARK: - Parser Errors

public enum ParserError: Error, LocalizedError {
    case invalidMountSpec(String)
    case invalidPortSpec(String)
    case invalidMemorySpec(String)
    case invalidRlimitSpec(String)

    public var errorDescription: String? {
        switch self {
        case .invalidMountSpec(let msg): return msg
        case .invalidPortSpec(let msg): return msg
        case .invalidMemorySpec(let msg): return msg
        case .invalidRlimitSpec(let msg): return msg
        }
    }
}
