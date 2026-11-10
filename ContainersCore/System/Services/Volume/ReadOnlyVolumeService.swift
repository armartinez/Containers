//
//  ReadOnlyVolumeService.swift
//  Containers
//
//  The volumes in the CLI's folder, while its API server runs.
//
//  Created by Axel Martinez on 2026/11/06.
//

import Foundation
import Logging

/// A volume service that only reads the volumes in the system's folder, beside the CLI's API server.
///
/// The API server reads volumes only when it boots, so it would go on listing a different set than the folder holds.
struct ReadOnlyVolumeService: VolumeService {
    let volumesRoot: URL
    let log: Logger

    init(appRoot: URL, log: Logger) {
        self.volumesRoot = appRoot.appendingPathComponent("volumes")
        self.log = log
    }

    func create(name: String, labels: [String: String], options: [String: String], sizeInBytes: UInt64?) throws -> Volume {
        throw ContainerCLIError.apiServerRunning
    }

    func delete(named name: String, inUseBy containerIDs: [String]) throws {
        throw ContainerCLIError.apiServerRunning
    }
}
