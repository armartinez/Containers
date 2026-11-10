//
//  NetworkConfiguration.swift
//  Containers
//
//  Created by Axel Martinez on 2026/10/31.
//

import ContainerizationError
import ContainerizationExtras
import Foundation

/// A network containers attach to, kept in the system folder's `networks` store so a folder can be shared with the CLI.
public struct NetworkConfiguration: Codable, Sendable, Identifiable, Equatable {
    /// The network the system makes for containers that name no other.
    public static let defaultName = "default"

    static let roleLabel = "com.apple.container.resource.role"
    static let builtinRole = "builtin"
    static let vmnetPlugin = "container-network-vmnet"

    public let name: String
    public let mode: NetworkMode
    public let creationDate: Date
    /// The IPv4 subnet asked for, or `nil` for one vmnet picks.
    public let ipv4Subnet: CIDRv4?
    public let ipv6Subnet: CIDRv6?
    public let labels: [String: String]
    public let plugin: String
    public let options: [String: String]

    public var id: String { name }

    /// Whether the system made the network itself, so it can't be deleted.
    public var isBuiltin: Bool {
        labels[Self.roleLabel] == Self.builtinRole
    }

    public init(
        name: String,
        mode: NetworkMode = .nat,
        ipv4Subnet: CIDRv4? = nil,
        ipv6Subnet: CIDRv6? = nil,
        labels: [String: String] = [:],
        creationDate: Date = Date()
    ) throws {
        guard Self.isValidName(name) else {
            throw ContainerizationError(.invalidArgument, message: "invalid network name: \(name)")
        }

        self.name = name
        self.mode = mode
        self.creationDate = creationDate
        self.ipv4Subnet = ipv4Subnet
        self.ipv6Subnet = ipv6Subnet
        self.labels = labels
        self.plugin = Self.vmnetPlugin
        self.options = [:]
    }

    /// The built-in network, with the subnet the system's settings ask for.
    static func builtin(subnet: CIDRv4?) throws -> NetworkConfiguration {
        try NetworkConfiguration(name: defaultName, ipv4Subnet: subnet, labels: [roleLabel: builtinRole])
    }

    /// Lowercase letters, digits, `.`, `_` and `-`, starting and ending with a letter or digit, up to 63 characters.
    public static func isValidName(_ name: String) -> Bool {
        name.range(of: #"^[a-z0-9](?:[a-z0-9._-]{0,61}[a-z0-9])?$"#, options: .regularExpression) != nil
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case id
        case creationDate
        case mode
        case ipv4Subnet
        case ipv6Subnet
        case labels
        case plugin
        case options
        case subnet
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        name = try container.decodeIfPresent(String.self, forKey: .name) ?? container.decode(String.self, forKey: .id)
        creationDate = try container.decodeIfPresent(Date.self, forKey: .creationDate) ?? Date(timeIntervalSince1970: 0)
        mode = try container.decode(NetworkMode.self, forKey: .mode)
        ipv4Subnet = try (container.decodeIfPresent(String.self, forKey: .ipv4Subnet) ?? container.decodeIfPresent(String.self, forKey: .subnet))
            .map { try CIDRv4($0) }
        ipv6Subnet = try container.decodeIfPresent(String.self, forKey: .ipv6Subnet).map { try CIDRv6($0) }
        labels = try container.decodeIfPresent([String: String].self, forKey: .labels) ?? [:]
        plugin = try container.decodeIfPresent(String.self, forKey: .plugin) ?? Self.vmnetPlugin
        options = try container.decodeIfPresent([String: String].self, forKey: .options) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(name, forKey: .name)
        try container.encode(creationDate, forKey: .creationDate)
        try container.encode(mode, forKey: .mode)
        try container.encodeIfPresent(ipv4Subnet?.description, forKey: .ipv4Subnet)
        try container.encodeIfPresent(ipv6Subnet?.description, forKey: .ipv6Subnet)
        try container.encode(labels, forKey: .labels)
        try container.encode(plugin, forKey: .plugin)
        try container.encode(options, forKey: .options)
    }
}

public enum NetworkMode: String, Codable, Sendable, CaseIterable {
    /// Containers reach outside networks through the Mac, which translates their addresses.
    case nat
    /// Containers reach only each other and the Mac.
    case hostOnly
}
