//
//  FilesystemEntityStore.swift
//  Containers
//
//  Generic JSON-based filesystem persistence for entity types.
//

import Foundation
import Logging

/// A simple JSON-based store that persists each entity in a folder of its own.
///
/// Laid out with `<id>/entity.json` under the store's folder, so a data folder can be shared with the CLI.
public struct FilesystemEntityStore<T: Codable & Sendable>: Sendable {
    private static var metadataFilename: String { "entity.json" }

    private let path: URL
    private let type: String
    private let logger: Logger

    public init(path: URL, type: String, log: Logger) throws {
        self.path = path
        self.type = type
        self.logger = log

        try FileManager.default.createDirectory(
            at: path,
            withIntermediateDirectories: true
        )
    }

    public func list() async throws -> [T] {
        let directories = try FileManager.default.contentsOfDirectory(
            at: path,
            includingPropertiesForKeys: nil
        )
        let decoder = JSONDecoder()

        var entities: [T] = []

        for directory in directories {
            let file = directory.appendingPathComponent(Self.metadataFilename)

            guard FileManager.default.fileExists(atPath: file.path) else {
                continue
            }

            do {
                let data = try Data(contentsOf: file)
                let entity = try decoder.decode(T.self, from: data)
                entities.append(entity)
            } catch {
                logger.warning(
                    "Failed to decode \(type) from \(directory.lastPathComponent): \(error)"
                )
            }
        }

        return entities
    }

    public func create(_ entity: T) async throws where T: Identifiable, T.ID == String {
        let directory = path.appendingPathComponent(entity.id)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let data = try JSONEncoder().encode(entity)

        try data.write(to: directory.appendingPathComponent(Self.metadataFilename))
    }

    /// Deletes the entity's folder, with anything else kept in it.
    public func delete(_ id: String) async throws {
        let directory = path.appendingPathComponent(id)

        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
}
