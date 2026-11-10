//
//  BuildPipeline+Export.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/09.
//

import Containerization
import Foundation

extension BuildPipeline {
    func handleExportTransfer(
        _ buildTransfer: BuildTransfer,
        sender: AsyncStream<ClientStream>.Continuation,
        buildID: String
    ) async throws {
        // BuildKit is trying to write export data through the filesync protocol
        // We need to receive the data and write it to the export directory

        logger.info(
            "Export transfer: direction=\(buildTransfer.direction), complete=\(buildTransfer.complete), source=\(buildTransfer.source), dataSize=\(buildTransfer.data.count)"
        )

        guard let exportPath = exportDestination(for: buildTransfer) else {
            logger.error("Could not resolve export destination for: \(buildTransfer.source)")
            return
        }

        logger.info("Writing export data to: \(exportPath.path)")

        // Create parent directory if needed
        let parentDir = exportPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        // Write or append the data
        if buildTransfer.data.count > 0 {
            if FileManager.default.fileExists(atPath: exportPath.path) {
                // Append to existing file
                let fileHandle = try FileHandle(forWritingTo: exportPath)
                defer { try? fileHandle.close() }
                try fileHandle.seekToEnd()
                try fileHandle.write(contentsOf: buildTransfer.data)
            } else {
                // Create new file
                try buildTransfer.data.write(to: exportPath)
            }
        }

        // Send acknowledgment back to BuildKit
        var response = ClientStream()
        response.buildID = buildID
        response.buildTransfer = BuildTransfer()
        response.buildTransfer.id = buildTransfer.id
        response.buildTransfer.source = buildTransfer.source
        response.buildTransfer.complete = true
        response.buildTransfer.direction = .outof
        response.buildTransfer.metadata = ["os": "linux"]

        response.packetType = .buildTransfer(response.buildTransfer)
        sender.yield(response)

        if buildTransfer.complete {
            logger.info("Export transfer complete for: \(exportPath.path)")
        }
    }

    private func exportDestination(for buildTransfer: BuildTransfer) -> URL? {
        let sourceLastPathComponent = URL(fileURLWithPath: buildTransfer.source)
            .lastPathComponent
        let destinations = config.exports.compactMap(\.destination)

        if let matchingDestination = destinations.first(where: {
            $0.lastPathComponent == sourceLastPathComponent
        }) {
            return matchingDestination
        }

        guard destinations.count == 1 else {
            return nil
        }

        return destinations[0]
    }
}
