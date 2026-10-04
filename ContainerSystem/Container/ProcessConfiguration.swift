//
//  ProcessConfiguration.swift
//  Containers
//
//  Local implementation of ProcessConfiguration (replaces ContainerResource.ProcessConfiguration)
//

import Foundation

/// Configuration for a process running inside a container.
public struct ProcessConfiguration: Sendable, Codable {

    /// Represents a user identity for the process.
    public enum User: Sendable, Codable, Equatable, CustomStringConvertible {
        case raw(userString: String)
        case id(uid: UInt32, gid: UInt32)

        public var description: String {
            switch self {
            case .raw(let userString):
                return userString
            case .id(let uid, let gid):
                return "\(uid):\(gid)"
            }
        }
    }

    /// Resource limit configuration.
    public struct Rlimit: Sendable, Codable {
        public let limit: String
        public let soft: UInt64
        public let hard: UInt64

        public init(limit: String, soft: UInt64, hard: UInt64) {
            self.limit = limit
            self.soft = soft
            self.hard = hard
        }
    }

    public var executable: String
    public var arguments: [String]
    public var environment: [String]
    public var workingDirectory: String
    public var terminal: Bool
    public var user: User
    public var supplementalGroups: [UInt32]
    public var rlimits: [Rlimit]

    public init(
        executable: String,
        arguments: [String] = [],
        environment: [String] = [],
        workingDirectory: String = "/",
        terminal: Bool = false,
        user: User = .id(uid: 0, gid: 0),
        supplementalGroups: [UInt32] = [],
        rlimits: [Rlimit] = []
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.terminal = terminal
        self.user = user
        self.supplementalGroups = supplementalGroups
        self.rlimits = rlimits
    }
}
