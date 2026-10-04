//
//  ContainerSnapshot.swift
//  Containers
//

import ContainerizationOCI
import Foundation

public enum ContainerStatus: String, Sendable, Codable, Hashable {
    case running
    case stopped
    case stopping
    case unknown
}

public struct ContainerSnapshot: Sendable, Codable {
    public var configuration: ContainerConfiguration
    public var status: ContainerStatus
    public var networks: [Attachment]
    public var startedDate: Date?

    public var id: String {
        configuration.id
    }

    public var platform: Platform {
        configuration.platform
    }

    public var volumeNames: [String] {
        configuration.mounts.compactMap(\.volumeName)
    }

    public var volumeFSs: [Filesystem] {
        configuration.mounts.filter(\.isVolume)
    }

    public init(
        configuration: ContainerConfiguration,
        status: ContainerStatus,
        networks: [Attachment],
        startedDate: Date? = nil
    ) {
        self.configuration = configuration
        self.status = status
        self.networks = networks
        self.startedDate = startedDate
    }
}
