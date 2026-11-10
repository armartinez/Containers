//
//  Attachment.swift
//  Containers
//
//  Local implementation of network attachment types (replaces ContainerResource network types)
//

import ContainerizationExtras
import Foundation

/// Represents a network attachment for a running container.
public struct Attachment: Sendable, Codable {
    public let network: String
    public let hostname: String
    public let ipv4Address: CIDRv4
    public let ipv4Gateway: IPv4Address
    public let ipv6Address: CIDRv6?
    public let macAddress: MACAddress?

    public init(
        network: String,
        hostname: String,
        ipv4Address: CIDRv4,
        ipv4Gateway: IPv4Address,
        ipv6Address: CIDRv6? = nil,
        macAddress: MACAddress? = nil
    ) {
        self.network = network
        self.hostname = hostname
        self.ipv4Address = ipv4Address
        self.ipv4Gateway = ipv4Gateway
        self.ipv6Address = ipv6Address
        self.macAddress = macAddress
    }
}

/// Configuration for attaching a container to a network.
public struct AttachmentConfiguration: Sendable, Codable {
    public let network: String
    public let options: AttachmentOptions

    public init(
        network: String,
        options: AttachmentOptions = AttachmentOptions()
    ) {
        self.network = network
        self.options = options
    }
}

/// Options for a network attachment.
public struct AttachmentOptions: Sendable, Codable {
    public let hostname: String
    public let macAddress: MACAddress?
    public let mtu: UInt32?
    public let aliases: [String]

    public init(hostname: String = "", macAddress: MACAddress? = nil, mtu: UInt32? = nil, aliases: [String] = []) {
        self.hostname = hostname
        self.macAddress = macAddress
        self.mtu = mtu
        self.aliases = aliases
    }

    private enum CodingKeys: String, CodingKey {
        case hostname
        case macAddress
        case mtu
        case aliases
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.hostname = try container.decode(String.self, forKey: .hostname)
        self.macAddress = try container.decodeIfPresent(MACAddress.self, forKey: .macAddress)
        self.mtu = try container.decodeIfPresent(UInt32.self, forKey: .mtu)
        self.aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
    }

    // Without the key when there are no aliases.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hostname, forKey: .hostname)
        try container.encodeIfPresent(macAddress, forKey: .macAddress)
        try container.encodeIfPresent(mtu, forKey: .mtu)

        if !aliases.isEmpty {
            try container.encode(aliases, forKey: .aliases)
        }
    }
}
