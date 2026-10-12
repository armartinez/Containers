//
//  TemporaryDirectory.swift
//  ContainerSystemTests
//
//  A unique scratch directory for a single test.
//

import Foundation

/// A directory under the system temp dir, unique per instance.
///
/// Tests pair this with `defer { directory.remove() }` so a failing
/// expectation still leaves the temp dir clean.
struct TemporaryDirectory {
    let url: URL

    init(_ name: String = "container-system-tests") throws {
        self.url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)")

        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    func appending(_ path: String) -> URL {
        url.appendingPathComponent(path)
    }

    /// Creates `path`, and any directory above it, holding `contents`.
    @discardableResult
    func write(_ contents: String, to path: String) throws -> URL {
        let file = appending(path)

        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: file)

        return file
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
