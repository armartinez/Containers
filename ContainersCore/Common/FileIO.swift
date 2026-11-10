//
//  FileIO.swift
//  Containers
//
//  Blocking filesystem and archive work.
//
//  Created by Axel Martinez on 2026/09/02.
//

import ContainerizationArchive
import Foundation

/// Copies, moves and archive (un)packing, performed on this actor's executor.
actor FileIO {
    static let shared = FileIO()

    func copyItem(at source: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: source, to: destination)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }

    func contents(of file: URL) throws -> Data {
        try Data(contentsOf: file)
    }

    /// Extracts `archive` into `directory`, returning the members it rejected.
    @discardableResult
    func extractArchive(at archive: URL, to directory: URL) throws -> [String] {
        let reader = try ArchiveReader(file: archive)

        return try reader.extractContents(to: directory)
    }

    func writeArchive(directory: URL, to destination: URL) throws {
        let writer = try ArchiveWriter(
            format: .pax,
            filter: .none,
            file: destination
        )

        try writer.archiveDirectory(directory)
        try writer.finishEncoding()
    }

    /// How much space the files under a directory take on disk. What is
    /// counted is what is allocated, so a sparse disk image counts for what has
    /// been written to it rather than for the size it was made at.
    func allocatedSize(of directory: URL) -> Int64 {
        let keys: [URLResourceKey] = [
            .totalFileAllocatedSizeKey, .isRegularFileKey,
        ]

        guard
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: keys,
                errorHandler: { _, _ in true }
            )
        else {
            return 0
        }

        var total: Int64 = 0

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else {
                continue
            }

            total += Int64(values.totalFileAllocatedSize ?? 0)
        }

        return total
    }
}
