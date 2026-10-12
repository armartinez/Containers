//
//  ContainersServiceTests.swift
//  ContainerSystemTests
//
//  Created by Axel Martinez on 2026/02/08.
//

import Containerization
import ContainerizationError
import ContainerizationOCI
import Foundation
import Logging
import Testing

@testable import ContainerSystem

@Suite("Containers service")
struct ContainersServiceTests {
    private func makeService(in directory: TemporaryDirectory) throws -> ContainersService {
        let log = Logger(label: "tests.containers")
        let imagesRoot = directory.appending("images")
        let contentStore = try LocalContentStore(path: imagesRoot.appendingPathComponent("content"))
        let images = try ImagesService(
            contentStore: contentStore,
            imageStore: try ImageStore(path: imagesRoot, contentStore: contentStore),
            snapshotsPath: imagesRoot.appendingPathComponent("snapshots"),
            log: log
        )

        return try ContainersService(appRoot: directory.url, imagesService: images, log: log)
    }

    /// Writes the files a container's bundle is read back from at launch.
    private func writeBundle(
        id: String,
        labels: [String: String] = [:],
        autoRemove: Bool = false,
        in directory: TemporaryDirectory
    ) throws {
        let path = directory.appending("containers/\(id)")

        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)

        var configuration = ContainerConfiguration(
            id: id,
            image: ImageDescription(
                reference: "docker.io/library/alpine:latest",
                descriptor: Descriptor(mediaType: "", digest: "", size: 0)
            ),
            process: ProcessConfiguration(executable: "/bin/sh")
        )
        configuration.labels = labels

        let bundle = Bundle(path: path)

        try bundle.write(filename: "config.json", value: configuration)
        try bundle.write(filename: "options.json", value: ContainerCreateOptions(autoRemove: autoRemove))
    }

    @Test("Empty root lists no containers")
    func emptyRootListsNothing() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let service = try makeService(in: directory)

        #expect(await service.list().isEmpty)
    }

    @Test("Bundles on disk load as stopped")
    func loadsBundlesAsStopped() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        try writeBundle(id: "web", in: directory)
        try writeBundle(id: "db", in: directory)

        let containers = try await makeService(in: directory).list()

        #expect(containers.map(\.id) == ["db", "web"])
        #expect(containers.allSatisfy { $0.status == .stopped })
    }

    @Test("Auto-remove bundles are reaped at launch")
    func reapsAutoRemoveBundles() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        try writeBundle(id: "keep", in: directory)
        try writeBundle(id: "temporary", autoRemove: true, in: directory)

        let containers = try await makeService(in: directory).list()

        #expect(containers.map(\.id) == ["keep"])
        #expect(!FileManager.default.fileExists(atPath: directory.appending("containers/temporary").path))
    }

    @Test("Unreadable bundle is skipped")
    func skipsUnreadableBundle() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        try writeBundle(id: "web", in: directory)
        try directory.write("not a bundle", to: "containers/broken/notes.txt")

        let containers = try await makeService(in: directory).list()

        #expect(containers.map(\.id) == ["web"])
    }

    @Test("List filters by status, label and name")
    func filtersList() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        try writeBundle(id: "web-frontend", labels: ["tier": "web"], in: directory)
        try writeBundle(id: "web-backend", labels: ["tier": "api"], in: directory)
        try writeBundle(id: "db", labels: ["tier": "data"], in: directory)

        let service = try makeService(in: directory)

        #expect(await service.list(labelFilter: ["tier": "api"]).map(\.id) == ["web-backend"])
        #expect(await service.list(namePattern: "WEB").map(\.id) == ["web-backend", "web-frontend"])
        #expect(await service.list(status: .running).isEmpty)
        #expect(await service.list(status: .stopped).count == 3)
    }

    @Test("Delete removes the bundle")
    func deleteRemovesBundle() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        try writeBundle(id: "web", in: directory)

        let service = try makeService(in: directory)

        try await service.delete(id: "web")

        #expect(await service.list().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.appending("containers/web").path))
    }

    @Test("Unknown container throws not found")
    func unknownContainerThrows() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let service = try makeService(in: directory)

        await #expect(throws: ContainerizationError.self) {
            try await service.delete(id: "missing")
        }
        await #expect(throws: ContainerizationError.self) {
            try await service.stop(id: "missing", options: ContainerStopOptions())
        }
    }

    @Test("Stopped container can't exec")
    func stoppedContainerCannotExec() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        try writeBundle(id: "web", in: directory)

        let service = try makeService(in: directory)

        await #expect(throws: ContainerizationError.self) {
            _ = try await service.exec(id: "web", arguments: ["true"])
        }
        #expect(await service.resourceUsage().isEmpty)
    }
}
