//
//  BuildPipeline.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/09.
//

import Containerization
import ContainerizationOCI
import Foundation
import Logging

/// Custom build pipeline that uses ImagesService for image resolution instead of XPC
actor BuildPipeline {
    let config: Builder.BuildConfig
    let imagesService: ImagesService
    let contentStore: ContentStore
    let logger: Logger

    init(config: Builder.BuildConfig, imagesService: ImagesService, contentStore: ContentStore) {
        self.config = config
        self.imagesService = imagesService
        self.contentStore = contentStore
        var logger = Logger(label: "app.containers.sandboxed-pipeline")
        logger.logLevel = .debug
        self.logger = logger
    }

    func run<Receiver: AsyncSequence>(
        sender: AsyncStream<ClientStream>.Continuation,
        receiver: Receiver
    ) async throws where Receiver.Element == ServerStream {
        defer { sender.finish() }

        logger.info("Build pipeline started")

        var packetCount = 0

        for try await packet in receiver {
            try Task.checkCancellation()
            packetCount += 1

            if packetCount == 1 {
                logger.info("Received first packet from BuildKit")
            }

            // Log packet type
            switch packet.packetType {
            case .imageTransfer(let transfer):
                logger.debug("Packet #\(packetCount): ImageTransfer(stage:\(transfer.stage() ?? "nil"), method:\(transfer.method() ?? "nil"))")
            case .buildTransfer(let transfer):
                logger.debug("Packet #\(packetCount): BuildTransfer(stage:\(transfer.metadata["stage"] ?? "nil"), method:\(transfer.metadata["method"] ?? "nil"))")
            case .io(let io):
                if let message = String(data: io.data, encoding: .utf8),
                    !message.trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                {
                    logger.info("\(message)")
                    await config.statusUpdate?(message)
                }
            case .buildError(let error):
                logger.error("Build error: \(error.message)")
            case .commandComplete:
                logger.info("Build command completed")
                throw BuilderError.buildComplete
            case .none:
                logger.debug("Packet #\(packetCount): Empty")
            }

            // Handle different packet types
            if let imageTransfer = packet.getImageTransfer() {
                try await handleImageTransfer(imageTransfer, sender: sender, buildID: packet.buildID)
            } else if let buildTransfer = packet.getBuildTransfer() {
                try await handleBuildTransfer(buildTransfer, sender: sender, buildID: packet.buildID)
            } else if let io = packet.getIO() {
                try await handleIO(io, sender: sender, buildID: packet.buildID)
            }
        }

        logger.info("Build pipeline finished (\(packetCount) packets)")
        logger.info("Stream ended - build should be complete")
    }

    private func handleBuildTransfer(
        _ buildTransfer: BuildTransfer,
        sender: AsyncStream<ClientStream>.Continuation,
        buildID: String
    ) async throws {
        // BuildTransfer packets are used for syncing files (both build context and exports)
        let stage = buildTransfer.metadata["stage"]
        let direction = buildTransfer.direction

        logger.info("BuildTransfer: stage=\(stage ?? "nil"), direction=\(direction), source=\(buildTransfer.source), dataSize=\(buildTransfer.data.count)")

        switch stage {
        case "fssync":
            // Handle build context file sync
            try await handleFSSyncTransfer(buildTransfer, sender: sender, buildID: buildID)
        case "export", nil:
            // Handle export file write - BuildKit is trying to write the export tar
            logger.info("Handling export transfer")
            try await handleExportTransfer(buildTransfer, sender: sender, buildID: buildID)
        default:
            logger.warning("Ignoring BuildTransfer with unknown stage: \(stage ?? "unknown")")
        }
    }
}
