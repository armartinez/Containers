//
//  SystemConfiguration.swift
//  Containers
//
//  Created by Axel Martinez on 2026/10/30.
//

import Configuration
import ConfigurationTOML
import Foundation
import SystemPackage

/// The container system's settings, kept in a `config.toml` in the system's folder, with the container CLI's
/// defaults for whatever the file leaves out.
///
/// With container CLI compatibility on, the file is the CLI's, so both set up and create things alike.
public struct SystemConfiguration: Equatable, Sendable {
    public var kernelURL: String
    public var kernelBinaryPath: String
    /// `nil` for a kernel URL of the user's own given without one, which can't be installed.
    public var kernelDigest: String?
    public var initImage: String
    public var builderImage: String
    public var buildRosetta: Bool
    public var buildCPUs: Int
    public var buildMemoryInBytes: UInt64
    public var containerCPUs: Int
    public var containerMemoryInBytes: UInt64
    public var dnsDomain: String?
    /// The registry for image references that don't name one.
    public var registryDomain: String
    /// The IPv4 subnet for the built-in network, or `nil` for one vmnet picks.
    public var subnet: String?

    /// CLI 1.6.1's defaults.
    public static let defaults = SystemConfiguration(
        kernelURL: "https://github.com/kata-containers/kata-containers/releases/download/3.32.0/kata-static-3.32.0-arm64.tar.zst",
        kernelBinaryPath: "opt/kata/share/kata-containers/vmlinux-6.18.35-197-debug",
        kernelDigest: "sha256:8736c054d9223974735394f822000823baef509e1c33405ec798240fa9b6e4b5",
        initImage: "ghcr.io/apple/containerization/vminit:0.53.0",
        builderImage: "ghcr.io/apple/container-builder-shim/builder:0.13.2",
        buildRosetta: true,
        buildCPUs: 2,
        buildMemoryInBytes: 2048 * 1024 * 1024,
        containerCPUs: 4,
        containerMemoryInBytes: 1024 * 1024 * 1024,
        dnsDomain: nil,
        registryDomain: "docker.io",
        subnet: nil
    )

    /// Where the settings live in a system's folder; for the CLI's, the copy `container system start` keeps there.
    static func file(in appRoot: URL) -> URL {
        appRoot.appending(path: "config/config.toml")
    }

    /// The defaults the CLI's installer ships, below the user's own settings.
    static let installDefaultsFile = URL(filePath: "/usr/local/etc/container/config.toml")

    /// Reads the settings for a system's folder.
    ///
    /// - Parameters:
    ///   - appRoot: The folder the system keeps its data in.
    ///   - includingInstallDefaults: Whether the CLI's installed defaults apply, as they do to the CLI's folder.
    /// - Returns: The folder's settings, with the defaults for any the files don't set.
    static func load(appRoot: URL, includingInstallDefaults: Bool) async -> SystemConfiguration {
        await load(files: [file(in: appRoot)] + (includingInstallDefaults ? [installDefaultsFile] : []))
    }

    /// Reads layered files, highest precedence first.
    ///
    /// A file the sandbox can't read, or that isn't valid, is skipped, so its settings fall back to the defaults.
    static func load(files: [URL]) async -> SystemConfiguration {
        var providers: [any ConfigProvider] = []

        for file in files where FileManager.default.isReadableFile(atPath: file.path(percentEncoded: false)) {
            if let provider = try? await FileProvider<TOMLSnapshot>(filePath: FilePath(file.path(percentEncoded: false))) {
                providers.append(provider)
            }
        }

        guard !providers.isEmpty else { return .defaults }

        return SystemConfiguration(reader: ConfigReader(providers: providers))
    }

    init(reader: ConfigReader) {
        let defaults = Self.defaults
        let kernelURL = reader.string(forKey: "kernel.url") ?? defaults.kernelURL

        self.kernelURL = kernelURL
        self.kernelBinaryPath = reader.string(forKey: "kernel.binaryPath") ?? defaults.kernelBinaryPath
        self.kernelDigest = reader.string(forKey: "kernel.digest") ?? (kernelURL == defaults.kernelURL ? defaults.kernelDigest : nil)
        self.initImage = reader.string(forKey: "vminit.image") ?? defaults.initImage
        self.builderImage = reader.string(forKey: "build.image") ?? defaults.builderImage
        self.buildRosetta = reader.bool(forKey: "build.rosetta") ?? defaults.buildRosetta
        self.buildCPUs = reader.int(forKey: "build.cpus") ?? defaults.buildCPUs
        self.buildMemoryInBytes = reader.string(forKey: "build.memory").flatMap(ByteSize.bytes(from:)) ?? defaults.buildMemoryInBytes
        self.containerCPUs = reader.int(forKey: "container.cpus") ?? defaults.containerCPUs
        self.containerMemoryInBytes =
            reader.string(forKey: "container.memory").flatMap(ByteSize.bytes(from:)) ?? defaults.containerMemoryInBytes
        self.dnsDomain = reader.string(forKey: "dns.domain")
        self.registryDomain = reader.string(forKey: "registry.domain") ?? defaults.registryDomain
        self.subnet = reader.string(forKey: "network.subnet")
    }

    init(
        kernelURL: String,
        kernelBinaryPath: String,
        kernelDigest: String?,
        initImage: String,
        builderImage: String,
        buildRosetta: Bool,
        buildCPUs: Int,
        buildMemoryInBytes: UInt64,
        containerCPUs: Int,
        containerMemoryInBytes: UInt64,
        dnsDomain: String?,
        registryDomain: String,
        subnet: String?
    ) {
        self.kernelURL = kernelURL
        self.kernelBinaryPath = kernelBinaryPath
        self.kernelDigest = kernelDigest
        self.initImage = initImage
        self.builderImage = builderImage
        self.buildRosetta = buildRosetta
        self.buildCPUs = buildCPUs
        self.buildMemoryInBytes = buildMemoryInBytes
        self.containerCPUs = containerCPUs
        self.containerMemoryInBytes = containerMemoryInBytes
        self.dnsDomain = dnsDomain
        self.registryDomain = registryDomain
        self.subnet = subnet
    }

    /// The settings with only what differs from the defaults, so a later default still applies
    /// to what was never changed.
    var tomlText: String {
        let defaults = Self.defaults
        var sections: [(name: String, entries: [(key: String, value: String)])] = []

        func add(_ section: String, _ key: String, _ value: String) {
            if let index = sections.firstIndex(where: { $0.name == section }) {
                sections[index].entries.append((key, value))
            } else {
                sections.append((section, [(key, value)]))
            }
        }

        if kernelURL != defaults.kernelURL { add("kernel", "url", Self.quoted(kernelURL)) }
        if kernelBinaryPath != defaults.kernelBinaryPath { add("kernel", "binaryPath", Self.quoted(kernelBinaryPath)) }
        if let kernelDigest, kernelDigest != defaults.kernelDigest { add("kernel", "digest", Self.quoted(kernelDigest)) }
        if initImage != defaults.initImage { add("vminit", "image", Self.quoted(initImage)) }
        if builderImage != defaults.builderImage { add("build", "image", Self.quoted(builderImage)) }
        if buildRosetta != defaults.buildRosetta { add("build", "rosetta", String(buildRosetta)) }
        if buildCPUs != defaults.buildCPUs { add("build", "cpus", String(buildCPUs)) }
        if buildMemoryInBytes != defaults.buildMemoryInBytes { add("build", "memory", Self.quoted("\(buildMemoryInBytes)b")) }
        if containerCPUs != defaults.containerCPUs { add("container", "cpus", String(containerCPUs)) }
        if containerMemoryInBytes != defaults.containerMemoryInBytes {
            add("container", "memory", Self.quoted("\(containerMemoryInBytes)b"))
        }
        if let dnsDomain { add("dns", "domain", Self.quoted(dnsDomain)) }
        if registryDomain != defaults.registryDomain { add("registry", "domain", Self.quoted(registryDomain)) }
        if let subnet { add("network", "subnet", Self.quoted(subnet)) }

        return sections.map { section in
            (["[\(section.name)]"] + section.entries.map { "\($0.key) = \($0.value)" }).joined(separator: "\n")
        }
        .joined(separator: "\n\n") + (sections.isEmpty ? "" : "\n")
    }

    /// A TOML basic string.
    private static func quoted(_ value: String) -> String {
        var escaped = ""

        for character in value.unicodeScalars {
            switch character {
            case "\"": escaped += "\\\""
            case "\\": escaped += "\\\\"
            case "\n": escaped += "\\n"
            case "\t": escaped += "\\t"
            case "\r": escaped += "\\r"
            default:
                if character.value < 0x20 || character.value == 0x7F {
                    escaped += String(format: "\\u%04X", character.value)
                } else {
                    escaped.unicodeScalars.append(character)
                }
            }
        }

        return "\"\(escaped)\""
    }

    /// Saves the settings in a system's folder, or removes the file when nothing differs from the defaults.
    func write(to appRoot: URL) throws {
        let file = Self.file(in: appRoot)
        let text = tomlText

        guard !text.isEmpty else {
            try? FileManager.default.removeItem(at: file)
            return
        }

        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file, options: .atomic)
    }

    /// The value for a key the app looks up by name.
    func value(for key: DefaultsStore.Key) -> String? {
        switch key {
        case .defaultInitImage: initImage
        case .defaultBuilderImage: builderImage
        case .defaultKernelURL: kernelURL
        case .defaultKernelBinaryPath: kernelBinaryPath
        case .defaultKernelDigest: kernelDigest
        case .defaultDNSDomain: dnsDomain
        case .buildRosetta: String(buildRosetta)
        case .defaultContainerCPUs: String(containerCPUs)
        case .defaultContainerMemory: String(containerMemoryInBytes)
        case .defaultBuildCPUs: String(buildCPUs)
        case .defaultBuildMemory: String(buildMemoryInBytes)
        case .registryDomain: registryDomain
        }
    }
}
