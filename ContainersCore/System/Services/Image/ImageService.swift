//
//  ImageService.swift
//  Containers
//
//  The images the system keeps in its folder, and the snapshots containers run from.
//
//  Created by Axel Martinez on 2026/11/06.
//

import Containerization
import ContainerizationError
import ContainerizationExtras
import ContainerizationOCI
import Foundation

/// A service that keeps the system's images, and unpacks them for containers to run.
protocol ImageService: Sendable {
    // Requirements so that both variants share the reads in the extension below, written once. A
    // requirement can't be private, so the rest of the module sees the stores too: go through the
    // service's methods instead. Only the build pipeline uses `contentStore` itself, since BuildKit
    // reads and writes its blobs through it.
    var imageStore: ImageStore { get }

    /// The content the image store's images are made of, which a build also reads and writes.
    var contentStore: ContentStore { get }

    /// The folder unpacked images are kept in, one snapshot per platform.
    var snapshotsPath: URL { get }

    func pull(
        reference: String,
        platform: Platform?,
        insecure: Bool,
        auth: Authentication?,
        progressUpdate: ProgressHandler?
    ) async throws -> ImageDescription

    func unpack(description: ImageDescription, platform: Platform?, progressUpdate: ProgressHandler?) async throws

    func load(from directory: URL, force: Bool) async throws -> ([ImageDescription], [String])

    func delete(reference: String, garbageCollect: Bool) async throws
}

extension ImageService {
    static var snapshotFilename: String { "snapshot" }
    static var snapshotInfoFilename: String { "snapshot-info" }

    /// List all images in the store.
    func list() async throws -> [ImageDescription] {
        try await imageStore.list().map(\.description)
    }

    /// The image stored under a reference.
    func image(for reference: String) async throws -> Containerization.Image {
        try await imageStore.get(reference: reference)
    }

    /// The environment variables an image's configuration sets for its process.
    func environment(of description: ImageDescription, platform: Platform) async throws -> [String] {
        let image = try await imageStore.get(reference: description.reference)

        return try await image.config(for: platform).config?.env ?? []
    }

    /// Get a Filesystem representing the unpacked image snapshot.
    func getImageSnapshot(description: ImageDescription, platform: Platform) async throws -> Filesystem {
        let image = try await imageStore.get(reference: description.reference)
        let directory = try await snapshotDirectory(for: image, platform: platform)
        let info = directory.appendingPathComponent(Self.snapshotInfoFilename)

        guard FileManager.default.fileExists(atPath: info.path),
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(Self.snapshotFilename).path)
        else {
            throw ContainerizationError(
                .notFound,
                message: "image snapshot not found at \(directory.path). Was the image unpacked?"
            )
        }

        return try JSONDecoder().decode(Filesystem.self, from: Data(contentsOf: info))
    }

    /// Save images to an OCI layout directory.
    func save(references: [String], out: URL, platform: Platform?) async throws {
        try await imageStore.save(references: references, out: out, platform: platform)
    }

    func pull(reference: String, platform: Platform?, insecure: Bool, progressUpdate: ProgressHandler?) async throws -> ImageDescription {
        try await pull(reference: reference, platform: platform, insecure: insecure, auth: nil, progressUpdate: progressUpdate)
    }

    /// One folder per platform manifest, named for its digest.
    func snapshotDirectory(for image: Containerization.Image, platform: Platform) async throws -> URL {
        let descriptor = try await image.descriptor(for: platform)

        return snapshotsPath.appendingPathComponent(descriptor.digest.digestHex, isDirectory: true)
    }
}
