//
//  PublishSocket.swift
//  Containers
//
//  Local implementation of PublishSocket (replaces ContainerResource.PublishSocket)
//

import Foundation
import SystemPackage

/// Represents a socket that should be published from container to host.
public struct PublishSocket: Sendable, Codable {
    public var containerPath: URL
    public var hostPath: URL
    public var permissions: FilePermissions?

    public init(
        containerPath: URL,
        hostPath: URL,
        permissions: FilePermissions? = nil
    ) {
        self.containerPath = containerPath
        self.hostPath = hostPath
        self.permissions = permissions
    }
}

// Paths are stored as plain strings, so a data folder can be shared with the CLI.
extension PublishSocket {
    enum CodingKeys: String, CodingKey {
        case containerPath
        case hostPath
        case permissions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let containerPath = try container.decode(String.self, forKey: .containerPath)
        let hostPath = try container.decode(String.self, forKey: .hostPath)

        self.containerPath = URL(filePath: containerPath)
        self.hostPath = URL(filePath: hostPath)
        self.permissions = try container.decodeIfPresent(FilePermissions.self, forKey: .permissions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(containerPath.path(percentEncoded: false), forKey: .containerPath)
        try container.encode(hostPath.path(percentEncoded: false), forKey: .hostPath)
        try container.encodeIfPresent(permissions, forKey: .permissions)
    }
}
