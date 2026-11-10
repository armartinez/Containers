//
//  DefaultImageService.swift
//  Containers
//
//  In-process image management service wrapping ImageStore and EXT4Unpacker.
//
//  Created by Axel on 17/3/26.
//

import Containerization
import ContainerizationError
import ContainerizationExtras
import ContainerizationOCI
import ContainerizationOS
import Foundation
import Logging

/// A service that handles container images, wrapping ImageStore and EXT4Unpacker.
struct DefaultImageService: ImageService {
    let imageStore: ImageStore
    let contentStore: ContentStore
    let snapshotsPath: URL
    private let ingestPath: URL
    private let log: Logger

    init(contentStore: ContentStore, imageStore: ImageStore, snapshotsPath: URL, log: Logger) throws {
        self.contentStore = contentStore
        self.imageStore = imageStore
        self.snapshotsPath = snapshotsPath
        self.ingestPath = snapshotsPath.appendingPathComponent("ingest")
        self.log = log

        try FileManager.default.createDirectory(at: ingestPath, withIntermediateDirectories: true)
    }

    // MARK: - Internal API

    /// Pull an image from a remote registry.
    func pull(
        reference: String,
        platform: Platform?,
        insecure: Bool,
        auth: Authentication?,
        progressUpdate: ProgressHandler?
    ) async throws -> ImageDescription {
        // Try provided auth first, then keychain, then environment variables
        let resolvedAuth = auth ?? resolveAuthentication(for: reference)

        let image = try await imageStore.pull(
            reference: reference,
            platform: platform,
            insecure: insecure,
            auth: resolvedAuth,
            progress: progressUpdate
        )
        return image.description
    }

    /// Unpack an image to an EXT4 block device for use as a container rootfs.
    func unpack(
        description: ImageDescription,
        platform: Platform?,
        progressUpdate: ProgressHandler?
    ) async throws {
        let image = try await imageStore.get(reference: description.reference)
        let targetPlatform = platform ?? .current
        let directory = try await snapshotDirectory(for: image, platform: targetPlatform)

        guard !FileManager.default.fileExists(atPath: directory.path) else { return }

        // Unpacked beside the snapshots and moved into place whole, so that neither the app nor
        // the CLI ever finds a snapshot half written.
        let ingestDirectory = ingestPath.appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(at: ingestDirectory, withIntermediateDirectories: true)

        do {
            let initImage = DefaultsStore.get(key: .defaultInitImage)
            let capacity = image.reference == initImage ? 512.mib() : 512.gib()
            let unpacker = EXT4Unpacker(capacityInBytes: capacity, journal: .init(defaultMode: .ordered))
            let mount = try await unpacker.unpack(
                image,
                for: targetPlatform,
                at: ingestDirectory.appendingPathComponent(Self.snapshotFilename),
                progress: progressUpdate
            )
            let snapshot = Filesystem.block(
                format: mount.type,
                source: directory.appendingPathComponent(Self.snapshotFilename).path,
                destination: mount.destination,
                options: mount.options
            )
            let info = try JSONEncoder().encode(snapshot)

            try info.write(to: ingestDirectory.appendingPathComponent(Self.snapshotInfoFilename))
            try FileManager.default.moveItem(at: ingestDirectory, to: directory)
        } catch let error as NSError where error.code == NSFileWriteFileExistsError {
            // Another unpack of the same image got there first.
            try? FileManager.default.removeItem(at: ingestDirectory)
        } catch {
            try? FileManager.default.removeItem(at: ingestDirectory)
            throw error
        }
    }

    /// Load images from an OCI layout directory on disk.
    func load(from directory: URL, force: Bool = false) async throws -> ([ImageDescription], [String]) {
        let images = try await imageStore.load(from: directory)
        let descriptions = images.map { $0.description }
        let references = descriptions.map { $0.reference }
        return (descriptions, references)
    }

    /// Tag an image with a new reference.
    func tag(existing: String, new: String) async throws -> ImageDescription {
        let image = try await imageStore.tag(existing: existing, new: new)
        return image.description
    }

    /// Push an image to a remote registry.
    func push(
        reference: String,
        platform: Platform?,
        insecure: Bool,
        auth: Authentication? = nil,
        progressUpdate: ProgressHandler?
    ) async throws {
        let resolvedAuth = auth ?? resolveAuthentication(for: reference)

        try await imageStore.push(
            reference: reference,
            platform: platform,
            insecure: insecure,
            auth: resolvedAuth,
            progress: progressUpdate
        )
    }

    /// Delete an image by reference.
    func delete(reference: String, garbageCollect: Bool = false) async throws {
        try await imageStore.delete(reference: reference, performCleanup: garbageCollect)
    }

    // MARK: - Private Helpers

    /// Security domain for keychain credential lookups.
    private static let keychainDomain = "app.containers.registry"

    /// Resolve authentication for a registry reference.
    private func resolveAuthentication(for reference: String) -> Authentication? {
        guard let hostname = Self.extractHostname(from: reference) else {
            return nil
        }

        // 1. Check environment variables (highest priority, enables CI/CD)
        let env = ProcessInfo.processInfo.environment
        if env["CONTAINER_REGISTRY_HOST"] == hostname,
            let user = env["CONTAINER_REGISTRY_USER"],
            let token = env["CONTAINER_REGISTRY_TOKEN"]
        {
            return BasicAuthentication(username: user, password: token)
        }

        // 2. Check macOS Keychain (credentials stored via `container registry login`)
        let keychain = KeychainHelper(securityDomain: Self.keychainDomain)
        if let keychainAuth = try? keychain.lookup(hostname: hostname) {
            return keychainAuth
        }

        // 3. No credentials found — return nil for anonymous access.
        // The RegistryClient handles the 401 → Bearer token exchange for public images.
        return nil
    }

    /// Extract the registry hostname from an image reference.
    private static func extractHostname(from reference: String) -> String? {
        guard let parsed = try? ContainerizationOCI.Reference.parse(reference)
        else {
            return nil
        }
        return parsed.resolvedDomain
    }
}
