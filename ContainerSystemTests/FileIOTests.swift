//
//  FileIOTests.swift
//  ContainerSystemTests
//
//  The blocking filesystem work the managers hand off.
//

import Foundation
import Testing

@testable import ContainerSystem

@Suite("File IO")
struct FileIOTests {

    @Test("Archive round trip")
    func archiveRoundTrip() async throws {
        let source = try TemporaryDirectory("archive-source")
        let destination = try TemporaryDirectory("archive-destination")
        defer {
            source.remove()
            destination.remove()
        }

        try source.write("index", to: "index.json")
        try source.write("layer bytes", to: "blobs/sha256/abc123")
        try source.write("nested", to: "blobs/sha256/deep/def456")

        let tar = destination.appending("layout.tar")

        try await FileIO.shared.writeArchive(
            directory: source.url,
            to: tar
        )

        let unpacked = destination.appending("unpacked")
        try FileManager.default.createDirectory(
            at: unpacked,
            withIntermediateDirectories: true
        )

        try await FileIO.shared.extractArchive(at: tar, to: unpacked)

        // Every file comes back at the same relative path, byte for byte.
        for path in ["index.json", "blobs/sha256/abc123", "blobs/sha256/deep/def456"] {
            let original = try Data(contentsOf: source.appending(path))
            let extracted = try Data(contentsOf: unpacked.appendingPathComponent(path))

            #expect(original == extracted, "\(path) did not survive the round trip")
        }
    }

    @Test("Copy keeps source")
    func copyKeepsSource() async throws {
        let directory = try TemporaryDirectory("copy")
        defer { directory.remove() }

        let source = try directory.write("dockerfile body", to: "context/Dockerfile")
        let destination = directory.appending("copy-of-context")

        try await FileIO.shared.copyItem(
            at: directory.appending("context"),
            to: destination
        )

        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(
            try Data(contentsOf: destination.appendingPathComponent("Dockerfile"))
                == Data("dockerfile body".utf8)
        )
    }

    @Test("Move removes source")
    func moveRemovesSource() async throws {
        let directory = try TemporaryDirectory("move")
        defer { directory.remove() }

        let source = try directory.write("export", to: "out.tar")
        let destination = directory.appending("saved.tar")

        try await FileIO.shared.moveItem(at: source, to: destination)

        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(try Data(contentsOf: destination) == Data("export".utf8))
    }

    @Test("Copy onto existing file fails")
    func copyOntoExistingFails() async throws {
        let directory = try TemporaryDirectory("copy-clash")
        defer { directory.remove() }

        let source = try directory.write("first", to: "a.txt")
        let destination = try directory.write("second", to: "b.txt")

        await #expect(throws: (any Error).self) {
            try await FileIO.shared.copyItem(at: source, to: destination)
        }

        // The destination is left as it was, not half-written.
        #expect(try Data(contentsOf: destination) == Data("second".utf8))
    }

    @Test("Read missing file fails")
    func readMissingFails() async throws {
        let directory = try TemporaryDirectory("read-missing")
        defer { directory.remove() }

        await #expect(throws: (any Error).self) {
            try await FileIO.shared.contents(
                of: directory.appending("absent.txt")
            )
        }
    }
}
