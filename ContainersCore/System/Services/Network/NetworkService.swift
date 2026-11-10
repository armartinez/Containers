//
//  NetworkService.swift
//  Containers
//
//  The networks containers attach to, as the system's folder keeps them.
//
//  Created by Axel Martinez on 2026/11/06.
//

import ContainerizationExtras
import Foundation
import Logging

/// A service that keeps the networks containers attach to.
protocol NetworkService: Sendable {
    // Requirements so that both variants share the reads in the extension below, written once. A
    // requirement can't be private, so the rest of the module sees them too: go through the service's
    // methods instead.
    var appRoot: URL { get }
    var log: Logger { get }

    /// Every network, sorted by name, the built-in one included.
    func list() async throws -> [NetworkConfiguration]

    func create(_ configuration: NetworkConfiguration) async throws

    /// Deletes a network, unless it's the built-in one or a container uses it.
    ///
    /// - Parameters:
    ///   - name: The network to delete.
    ///   - containerIDs: The containers configured to attach to the network, running or not.
    /// - Throws: An error if the network doesn't exist, is the built-in one, or a container uses it.
    func delete(named name: String, inUseBy containerIDs: [String]) async throws
}

extension NetworkService {
    /// The networks kept in the system's folder, whose directory is made the first time it's needed.
    func store() throws -> FilesystemEntityStore<NetworkConfiguration> {
        try FilesystemEntityStore(path: appRoot.appendingPathComponent("networks"), type: "networks", log: log)
    }

    func list() async throws -> [NetworkConfiguration] {
        try await read().networks
    }

    /// Every network, sorted by name, without writing the folder.
    ///
    /// - Returns: The networks, the built-in one included, and the built-in one again if the folder doesn't store it yet.
    func read() async throws -> (networks: [NetworkConfiguration], unstoredBuiltin: NetworkConfiguration?) {
        var networks = try await store().list()
        var unstoredBuiltin: NetworkConfiguration?

        if !networks.contains(where: { $0.name == NetworkConfiguration.defaultName }) {
            let builtin = try NetworkConfiguration.builtin(subnet: DefaultsStore.configuration.subnet.flatMap { try? CIDRv4($0) })

            networks.append(builtin)
            unstoredBuiltin = builtin
        }

        return (networks.sorted { $0.name < $1.name }, unstoredBuiltin)
    }
}
