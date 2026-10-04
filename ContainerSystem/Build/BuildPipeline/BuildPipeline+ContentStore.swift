//
//  BuildPipeline+ContentStore.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/09.
//

import Containerization
import ContainerizationOCI
import Foundation

extension BuildPipeline {
    func handleContentStoreRequest(
        _ imageTransfer: ImageTransfer,
        sender: AsyncStream<ClientStream>.Continuation,
        buildID: String
    ) async throws {
        let method = imageTransfer.metadata["method"]

        switch method {
        case "/containerd.services.content.v1.Content/Info":
            try await handleContentStoreInfo(imageTransfer, sender: sender, buildID: buildID)
        case "/containerd.services.content.v1.Content/ReaderAt":
            try await handleContentStoreReaderAt(imageTransfer, sender: sender, buildID: buildID)
        default:
            logger.error("Unknown content-store method: \(method ?? "nil")")
        }
    }

    private func handleContentStoreInfo(
        _ packet: ImageTransfer,
        sender: AsyncStream<ClientStream>.Continuation,
        buildID: String
    ) async throws {
        // BuildKit is asking for information about a blob in the content store
        let digest = packet.tag

        // Get the blob descriptor from content store
        let descriptor = try await contentStore.get(digest: digest)
        let size = try descriptor?.size()

        var transfer = ImageTransfer()
        transfer.id = packet.id
        transfer.tag = digest
        transfer.metadata = [
            "os": "linux",
            "stage": "content-store",
            "method": "/containerd.services.content.v1.Content/Info",
        ]
        if let size = size {
            transfer.metadata["size"] = String(size)
        }
        transfer.complete = true
        transfer.direction = .into

        var response = ClientStream()
        response.buildID = buildID
        response.imageTransfer = transfer
        response.packetType = .imageTransfer(transfer)
        sender.yield(response)
    }

    private func handleContentStoreReaderAt(
        _ packet: ImageTransfer,
        sender: AsyncStream<ClientStream>.Continuation,
        buildID: String
    ) async throws {
        // BuildKit is asking to read data from a blob
        let digest = packet.descriptor.digest
        let offset = UInt64(packet.metadata["offset"] ?? "0") ?? 0
        let length = Int(packet.metadata["length"] ?? "0") ?? 0

        guard let descriptor = try await contentStore.get(digest: digest) else {
            logger.error("Blob not found in content store: \(digest)")
            throw BuilderError.imageNotInContentStore(digest)
        }

        // If offset and length are both 0, this is a metadata request (just size)
        if offset == 0 && length == 0 {
            let size = try descriptor.size()
            var transfer = ImageTransfer()
            transfer.id = packet.id
            transfer.tag = digest
            transfer.metadata = [
                "os": "linux",
                "stage": "content-store",
                "method": "/containerd.services.content.v1.Content/ReaderAt",
                "size": String(size),
            ]
            transfer.complete = true
            transfer.direction = .into
            transfer.data = Data()

            var response = ClientStream()
            response.buildID = buildID
            response.imageTransfer = transfer
            response.packetType = .imageTransfer(transfer)
            sender.yield(response)
            return
        }

        // Read the blob data at the requested offset and length
        guard let data = try descriptor.data(offset: offset, length: length)
        else {
            logger.error("Failed to read data from content store: digest=\(digest), offset=\(offset), length=\(length)")
            throw BuilderError.imageNotInContentStore(digest)
        }

        var transfer = ImageTransfer()
        transfer.id = packet.id
        transfer.tag = digest
        transfer.metadata = [
            "os": "linux",
            "stage": "content-store",
            "method": "/containerd.services.content.v1.Content/ReaderAt",
        ]
        transfer.complete = true
        transfer.direction = .into
        transfer.data = data

        var response = ClientStream()
        response.buildID = buildID
        response.imageTransfer = transfer
        response.packetType = .imageTransfer(transfer)
        sender.yield(response)
    }
}
