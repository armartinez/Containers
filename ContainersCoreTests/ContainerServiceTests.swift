//
//  ContainerServiceTests.swift
//  ContainersCoreTests
//
//  Created by Axel Martinez on 2026/02/08.
//

import Containerization
import ContainerizationError
import ContainerizationOCI
import Foundation
import Logging
import Testing

@testable import ContainersCore

@Suite("Container service")
struct ContainerServiceTests {
    private func makeService(in directory: TemporaryDirectory) throws -> DefaultContainerService {
        let log = Logger(label: "tests.containers")
        let imagesRoot = directory.appending("images")
        let contentStore = try LocalContentStore(path: imagesRoot.appendingPathComponent("content"))
        let images = try DefaultImageService(
            contentStore: contentStore,
            imageStore: try ImageStore(path: imagesRoot, contentStore: contentStore),
            snapshotsPath: imagesRoot.appendingPathComponent("snapshots"),
            log: log
        )

        return try DefaultContainerService(
            appRoot: directory.url,
            imageService: images,
            networkService: DefaultNetworkService(appRoot: directory.url, log: log),
            log: log
        )
    }

    private func makeReadOnlyService(in directory: TemporaryDirectory) -> ReadOnlyContainerService {
        ReadOnlyContainerService(appRoot: directory.url, log: Logger(label: "tests.containers"))
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
                descriptor: Descriptor(mediaType: "", digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", size: 0)
            ),
            process: ProcessConfiguration(executable: "/bin/sh")
        )
        configuration.labels = labels

        let bundle = Bundle(path: path)

        try bundle.write(filename: "config.json", value: configuration)
        try bundle.write(filename: "options.json", value: ContainerCreateOptions(autoRemove: autoRemove))
    }

    @Test("A container is set up as the CLI's runtime sets it up")
    func configuresContainerAsCLI() throws {
        var configuration = ContainerConfiguration(
            id: "web",
            image: ImageDescription(
                reference: "docker.io/library/alpine:latest",
                descriptor: Descriptor(mediaType: "", digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", size: 0)
            ),
            process: ProcessConfiguration(executable: "/bin/sh")
        )
        configuration.sysctls = ["net.core.somaxconn": "1024"]
        configuration.useInit = true
        configuration.shmSize = 1_048_576
        configuration.maskedPaths = []
        configuration.networks = [AttachmentConfiguration(network: "default", options: AttachmentOptions(hostname: "web.test."))]
        configuration.dns = ContainerConfiguration.DNSConfiguration(nameservers: [])

        var czConfig = LinuxContainer.Configuration()

        try DefaultContainerService.configureContainer(
            czConfig: &czConfig,
            config: configuration,
            precomputedMounts: [],
            precomputedSockets: [],
            defaultNameservers: ["192.168.64.1"]
        )

        #expect(czConfig.sysctl["net.core.somaxconn"] == "1024")
        #expect(czConfig.sysctl["vm.overcommit_memory"] == "1")
        #expect(czConfig.sysctl["vm.max_map_count"] == "262144")
        #expect(czConfig.useInit)
        #expect(czConfig.maskedPaths.isEmpty)
        #expect(czConfig.readonlyPaths == LinuxContainer.defaultReadonlyPaths())
        #expect(czConfig.hostname == "web")
        #expect(czConfig.dns?.nameservers == ["192.168.64.1"])

        let shm = try #require(czConfig.mounts.first { $0.destination == "/dev/shm" })
        #expect(shm.options.filter { $0.hasPrefix("size=") } == ["size=1048576"])
    }

    @Test("Read-only, the CLI's auto-remove containers are kept, with unknown state")
    func readOnlyKeepsCLIContainers() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        try writeBundle(id: "cli-run", autoRemove: true, in: directory)

        let service = makeReadOnlyService(in: directory)
        let containers = await service.list()

        #expect(containers.map(\.id) == ["cli-run"])
        #expect(containers.first?.status == .unknown)
        #expect(FileManager.default.fileExists(atPath: directory.appending("containers/cli-run").path))
    }

    @Test("Read-only, the containers the CLI makes are picked up")
    func readOnlyReloadsCLIContainers() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let service = makeReadOnlyService(in: directory)

        try writeBundle(id: "made-by-cli", in: directory)
        await service.reload()

        #expect(await service.list().map(\.id) == ["made-by-cli"])
    }

    @Test("Lists a container the CLI created but never started")
    func listsUnstartedCLIContainer() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let path = directory.appending("containers/created-by-cli")
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)

        let kernel = try JSONDecoder().decode(
            Kernel.self,
            from: Data(#"{"commandLine": {"initArgs": [], "kernelArgs": []}, "path": "file:///tmp/k.bin", "platform": {"architecture": "arm64", "os": "linux"}}"#.utf8)
        )
        let configuration = ContainerConfiguration(
            id: "created-by-cli",
            image: ImageDescription(
                reference: "docker.io/library/alpine:latest",
                descriptor: Descriptor(mediaType: "", digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", size: 0)
            ),
            process: ProcessConfiguration(executable: "/bin/sh")
        )

        try Bundle(path: path).write(
            filename: "runtime-configuration.json",
            value: Bundle.RuntimeConfiguration(
                initialFilesystem: .block(source: "/tmp/init.ext4", destination: "/", options: ["ro"]),
                kernel: kernel,
                containerConfiguration: configuration,
                containerRootFilesystem: nil,
                options: nil
            )
        )

        let service = makeReadOnlyService(in: directory)

        #expect(await service.list().map(\.id) == ["created-by-cli"])
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
