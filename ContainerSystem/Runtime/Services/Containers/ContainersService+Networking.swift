//
//  ContainersService+Networking.swift
//  Containers
//
//  IP addresses for containers on the NAT network.
//
//  Created by Axel Martinez on 2026/10/24.
//

import ContainerizationError

extension ContainersService {
    func allocateIP(for id: String) throws -> (address: String, gateway: String) {
        let hostNumber = ipAllocations[id] ?? (UInt8(2)...254).first { !ipAllocations.values.contains($0) }

        guard let hostNumber else {
            throw ContainerizationError(.internalError, message: "no available IP addresses")
        }

        ipAllocations[id] = hostNumber
        return (address: "192.168.64.\(hostNumber)/24", gateway: "192.168.64.1")
    }

    func releaseIP(for id: String) {
        ipAllocations.removeValue(forKey: id)
    }
}
