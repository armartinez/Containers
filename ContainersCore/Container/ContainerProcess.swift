//
//  ContainerProcess.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/04.
//

import Foundation

public struct ContainerProcess: Sendable {
    public var uid: UInt32?
    public var gid: UInt32?
    public var workingDirectory: String?
    public var environments: [String] = []
    public var envFile: [String] = []
    public var tty = false
    public var user: String?

    public init() {}
}
