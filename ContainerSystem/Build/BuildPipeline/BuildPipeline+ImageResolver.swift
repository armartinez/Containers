//
//  BuildPipeline+ImageResolver.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/09.
//

import Containerization
import ContainerizationOCI
import Foundation

extension BuildPipeline {
    func handleImageTransfer(
        _ imageTransfer: ImageTransfer,
        sender: AsyncStream<ClientStream>.Continuation,
        buildID: String
    ) async throws {
        let stage = imageTransfer.metadata["stage"]
        let method = imageTransfer.metadata["method"]

        // Handle resolver requests
        if stage == "resolver" && method == "/resolve" {
            try await handleResolverRequest(imageTransfer, sender: sender, buildID: buildID)
            return
        }

        // Handle content-store requests
        if stage == "content-store" {
            try await handleContentStoreRequest(imageTransfer, sender: sender, buildID: buildID)
            return
        }

        logger.debug("Skipping ImageTransfer(stage=\(stage ?? "nil"), method=\(method ?? "nil"))")
    }

    private func handleResolverRequest(
        _ imageTransfer: ImageTransfer,
        sender: AsyncStream<ClientStream>.Continuation,
        buildID: String
    ) async throws {
        guard let ref = imageTransfer.ref() else {
            throw BuilderError.imageMissing
        }

        guard let platform = try imageTransfer.platform() else {
            throw BuilderError.platformMissing
        }

        logger.info("Resolving image: \(ref) for platform: \(platform.description)")

        let imageDescription = try await pullImage(reference: ref, platform: platform)

        guard let indexContent: Content = try await contentStore.get(digest: imageDescription.digest) else {
            throw BuilderError.imageNotFound
        }

        let index: Index = try indexContent.decode()

        for manifest in index.manifests {
            if manifest.platform == platform {
                guard let manifestContent: Content = try await contentStore.get(digest: manifest.digest) else {
                    continue
                }

                let manifestData: Manifest = try manifestContent.decode()

                guard
                    let ociImage: ContainerizationOCI.Image = try await contentStore.get(
                        digest: manifestData.config.digest
                    )
                else {
                    continue
                }

                let enc = JSONEncoder()
                let data = try enc.encode(ociImage)
                let transfer = try ImageTransfer(
                    id: imageTransfer.id,
                    digest: imageDescription.digest,
                    ref: ref,
                    platform: platform.description,
                    data: data
                )

                var response = ClientStream()
                response.buildID = buildID
                response.imageTransfer = transfer
                response.packetType = .imageTransfer(transfer)
                sender.yield(response)

                logger.info("Resolved: \(ref)")
                return
            }
        }

        throw BuilderError.unknownPlatformForImage(platform.description, ref)
    }

    private func pullImage(reference: String, platform: Platform) async throws -> ImageDescription {
        let normalizedRef = try Reference.normalized(reference).description

        // Check if image already exists
        let existingImages = try await imagesService.list()

        if let existing = existingImages.first(where: {
            $0.reference == normalizedRef || $0.reference == reference
        }) {
            logger.debug("Using existing image: \(normalizedRef)")
            return existing
        }

        // Pull the image
        logger.info("Pulling \(normalizedRef)...")

        let imageDescription = try await imagesService.pull(
            reference: normalizedRef,
            platform: platform,
            insecure: false,
            progressUpdate: { events in
                // Progress events are string-based (e.g., "add-items", "add-size")
            }
        )

        try await imagesService.unpack(description: imageDescription, platform: platform, progressUpdate: nil)

        logger.info("Pulled \(normalizedRef)")

        return imageDescription
    }
}
