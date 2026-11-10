//
//  FolderEventsTests.swift
//  ContainersCoreTests
//
//  Hearing about changes another process makes under a data folder.
//

import Foundation
import Testing

@testable import ContainersCore

@Suite("Folder events")
struct FolderEventsTests {

    @Test("Reports a changed file relative to the folder")
    func reportsChangedFile() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let changes = FolderEvents.changes(under: directory.url, latency: 0.05)

        // FSEvents starts reporting a moment after the stream is created.
        try await Task.sleep(for: .milliseconds(300))
        try directory.write("{}", to: "state.json")

        let paths = await firstBatch(of: changes, timeout: .seconds(5))

        #expect(paths?.contains("state.json") == true)
    }

    @Test("Reports a new entry inside a subfolder")
    func reportsNestedEntry() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        try directory.write("{}", to: "volumes/.keep")

        let changes = FolderEvents.changes(under: directory.url, latency: 0.05)

        try await Task.sleep(for: .milliseconds(300))
        try directory.write("{}", to: "volumes/data/entity.json")

        let paths = await firstBatch(of: changes, timeout: .seconds(5))

        #expect(paths?.contains { $0.hasPrefix("volumes/") } == true)
    }

    /// The first batch the stream yields, or `nil` if none arrives in time.
    private func firstBatch(of changes: AsyncStream<[String]>, timeout: Duration) async -> [String]? {
        await withTaskGroup(of: [String]?.self) { group in
            group.addTask {
                for await paths in changes {
                    return paths
                }

                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }

            let first = await group.next() ?? nil
            group.cancelAll()

            return first
        }
    }
}
