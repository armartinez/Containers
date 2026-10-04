//
//  FilesystemEntityStore.swift
//  Containers
//
//  Generic JSON-based filesystem persistence for entity types.
//

import Foundation
import Logging

/// A simple JSON-based store that persists entities as individual files in a directory.
public struct FilesystemEntityStore<T: Codable & Sendable>: Sendable {
    private let path: URL
    private let type: String
    private let logger: Logger
    private let metadataDir: URL

    public init(path: URL, type: String, log: Logger) throws {
        self.path = path
        self.type = type
        self.logger = log
        self.metadataDir = path.appendingPathComponent(".metadata")

        try FileManager.default.createDirectory(
            at: metadataDir,
            withIntermediateDirectories: true
        )
    }

    public func list() async throws -> [T] {
        let fm = FileManager.default

        guard fm.fileExists(atPath: metadataDir.path) else {
            return []
        }

        let contents = try fm.contentsOfDirectory(
            at: metadataDir,
            includingPropertiesForKeys: nil
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var entities: [T] = []

        for file in contents where file.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: file)
                let entity = try decoder.decode(T.self, from: data)
                entities.append(entity)
            } catch {
                logger.warning(
                    "Failed to decode \(type) from \(file.lastPathComponent): \(error)"
                )
            }
        }

        return entities
    }

    public func create(_ entity: T) async throws where T: Identifiable, T.ID == String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]

        let data = try encoder.encode(entity)
        let file = metadataDir.appendingPathComponent("\(entity.id).json")

        try data.write(to: file)
    }

    public func delete(_ id: String) async throws {
        let file = metadataDir.appendingPathComponent("\(id).json")

        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }
}
