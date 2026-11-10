//
//  ReadOnlyImageService.swift
//  Containers
//
//  The images in the CLI's folder, while its API server runs.
//
//  Created by Axel Martinez on 2026/11/06.
//

import Containerization
import ContainerizationExtras
import ContainerizationOCI
import Foundation

/// An image service that only reads the images in the system's folder, beside the CLI's API server.
struct ReadOnlyImageService: ImageService {
    let imageStore: ImageStore
    let contentStore: ContentStore
    let snapshotsPath: URL

    func pull(
        reference: String,
        platform: Platform?,
        insecure: Bool,
        auth: Authentication?,
        progressUpdate: ProgressHandler?
    ) throws -> ImageDescription {
        throw ContainerCLIError.apiServerRunning
    }

    func unpack(description: ImageDescription, platform: Platform?, progressUpdate: ProgressHandler?) throws {
        throw ContainerCLIError.apiServerRunning
    }

    func load(from directory: URL, force: Bool) throws -> ([ImageDescription], [String]) {
        throw ContainerCLIError.apiServerRunning
    }

    func delete(reference: String, garbageCollect: Bool) throws {
        throw ContainerCLIError.apiServerRunning
    }
}
