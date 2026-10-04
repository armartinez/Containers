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
