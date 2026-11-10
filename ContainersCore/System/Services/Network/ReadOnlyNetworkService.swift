//
//  ReadOnlyNetworkService.swift
//  Containers
//
//  The networks in the CLI's folder, while its API server runs.
//
//  Created by Axel Martinez on 2026/11/06.
//

import Foundation
import Logging

/// A network service that only reads the networks in the system's folder, beside the CLI's API server, which
/// stores the built-in network when it first starts.
struct ReadOnlyNetworkService: NetworkService {
    let appRoot: URL
    let log: Logger

    func create(_ configuration: NetworkConfiguration) throws {
        throw ContainerCLIError.apiServerRunning
    }

    func delete(named name: String, inUseBy containerIDs: [String]) throws {
        throw ContainerCLIError.apiServerRunning
    }
}
