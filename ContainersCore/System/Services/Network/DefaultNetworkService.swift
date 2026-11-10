//
//  DefaultNetworkService.swift
//  Containers
//
//  The networks containers attach to, as the system's folder keeps them.
//
//  Created by Axel Martinez on 2026/11/05.
//

import ContainerizationError
import ContainerizationExtras
import Foundation
import Logging

/// The networks kept in the system's folder, which containers attach to.
///
/// The interfaces containers get on them are ``DefaultContainerService``'s, as they change with each container's state.
struct DefaultNetworkService: NetworkService {
    let appRoot: URL
    let log: Logger

    /// Every network, sorted by name, with the built-in one stored the first time it's asked for.
    func list() async throws -> [NetworkConfiguration] {
        let (networks, unstoredBuiltin) = try await read()

        if let unstoredBuiltin {
            try await store().create(unstoredBuiltin)
        }

        return networks
    }

    func create(_ configuration: NetworkConfiguration) async throws {
        let networks = try await list()

        guard !networks.contains(where: { $0.name == configuration.name }) else {
            throw ContainerizationError(.exists, message: "network \(configuration.name) already exists")
        }

        if let subnet = configuration.ipv4Subnet,
            let overlap = networks.first(where: { other in
                other.ipv4Subnet.map { $0.lower.value <= subnet.upper.value && subnet.lower.value <= $0.upper.value } ?? false
            })
        {
            throw ContainerizationError(.exists, message: "IPv4 subnet \(subnet) overlaps network \(overlap.name)")
        }

        try await store().create(configuration)
    }

    func delete(named name: String, inUseBy containerIDs: [String]) async throws {
        guard let network = try await list().first(where: { $0.name == name }) else {
            throw ContainerizationError(.notFound, message: "network \(name) not found")
        }

        guard !network.isBuiltin else {
            throw ContainerizationError(.invalidArgument, message: "cannot delete builtin network: \(name)")
        }

        guard containerIDs.isEmpty else {
            let names = containerIDs.sorted().joined(separator: ", ")
            throw ContainerizationError(.invalidState, message: "cannot delete network \(name) used by containers: \(names)")
        }

        try await store().delete(name)
    }
}
