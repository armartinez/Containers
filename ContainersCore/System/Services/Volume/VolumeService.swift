//
//  VolumeService.swift
//  Containers
//
//  The volumes containers mount, as the system's folder keeps them.
//
//  Created by Axel Martinez on 2026/11/06.
//

import Foundation
import Logging

/// A service that keeps the volumes containers mount.
protocol VolumeService: Sendable {
    // Requirements so that both variants share the reads in the extension below, written once. A
    // requirement can't be private, so the rest of the module sees them too: go through the service's
    // methods instead.
    var volumesRoot: URL { get }
    var log: Logger { get }

    func create(name: String, labels: [String: String], options: [String: String], sizeInBytes: UInt64?) async throws -> Volume

    func delete(named name: String, inUseBy containerIDs: [String]) async throws
}

extension VolumeService {
    /// The volumes in the system's folder, whose directory is made the first time it's needed.
    func store() throws -> FilesystemEntityStore<Volume> {
        try FilesystemEntityStore<Volume>(path: volumesRoot, type: "volumes", log: log)
    }

    func list() async throws -> [Volume] {
        try await store().list()
    }
}
