//
//  ContainerResourceUsage.swift
//  Containers
//
//  Created by Axel Martinez on 15/09/2026.
//

import Foundation

public struct ContainerResourceUsage: Sendable {
    public let id: String
    public let memoryBytes: UInt64
    public let cpuUsageMicroseconds: UInt64
}
