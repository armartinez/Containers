//
//  ResourceUsage.swift
//  Containers
//
//  Created by Axel Martinez on 10/2/26.
//

struct ResourceUsage {
    static let zero = ResourceUsage(memoryUsage: 0, cpuUsage: 0, diskUsage: 0)

    let memoryUsage: Double  // in GB
    let cpuUsage: Double  // percentage
    let diskUsage: Double  // in GB
}
