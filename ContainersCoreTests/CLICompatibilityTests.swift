//
//  CLICompatibilityTests.swift
//  ContainersCoreTests
//
//  Reading and writing what apple/container's CLI keeps in a shared data folder.
//

import Containerization
import Foundation
import Logging
import Testing

@testable import ContainersCore

/// The fixtures are what apple/container 1.6 encodes for its own types. The CLI deletes a
/// container bundle it can't decode, so the app must write configurations the CLI can read.
@Suite("CLI compatibility")
struct CLICompatibilityTests {

    private static let containerConfiguration = """
        {"capAdd": ["CAP_NET_ADMIN"], "capDrop": ["CAP_SYS_ADMIN"], "creationDate": 800000000,
         "dns": {"domain": "local", "nameservers": ["1.1.1.1"], "options": ["ndots:1"], "searchDomains": ["x"]},
         "id": "web",
         "image": {"descriptor": {"digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "mediaType": "application/vnd.oci.image.index.v1+json", "size": 1234},
                   "reference": "docker.io/library/alpine:latest"},
         "initProcess": {"arguments": ["-c", "echo hi"], "environment": ["PATH=/usr/bin"], "executable": "/bin/sh",
                         "rlimits": [{"hard": 2048, "limit": "RLIMIT_NOFILE", "soft": 1024}], "supplementalGroups": [10],
                         "terminal": true, "user": {"raw": {"userString": "nobody"}}, "workingDirectory": "/root"},
         "labels": {"k": "v"},
         "mounts": [
            {"destination": "/a", "options": ["ro"], "source": "/tmp/a.img",
             "type": {"block": {"cache": {"on": {}}, "format": "ext4", "sync": {"fsync": {}}}}},
            {"destination": "/data", "options": [], "source": "/tmp/v/volume.img",
             "type": {"volume": {"cache": {"on": {}}, "format": "ext4", "name": "data", "sync": {"fsync": {}}}}},
            {"destination": "/share", "options": [], "source": "/tmp/share", "type": {"virtiofs": {}}},
            {"destination": "/tmp", "options": [], "source": "tmpfs", "type": {"tmpfs": {}}}],
         "maskedPaths": ["/proc/kcore"], "readonlyPaths": [],
         "networks": [{"network": "default", "options": {"aliases": ["api.example.test"], "hostname": "web", "mtu": 1400}}],
         "platform": {"architecture": "arm64", "os": "linux", "variant": "v8"},
         "publishedPorts": [{"containerPort": 80, "count": 1, "hostAddress": "127.0.0.1", "hostPort": 8080, "proto": "tcp"}],
         "publishedSockets": [{"containerPath": "/run/a.sock", "hostPath": "/tmp/a.sock"}],
         "readOnly": true, "resources": {"cpuOverhead": 1, "cpus": 2, "memoryInBytes": 1073741824}, "rosetta": false,
         "runtimeHandler": "container-runtime-linux", "ssh": false, "stopSignal": "SIGTERM", "sysctls": {},
         "useInit": true, "virtualization": false}
        """

    private static let image = """
        {"descriptor": {"digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
         "mediaType": "application/vnd.oci.image.index.v1+json", "size": 1}, "reference": "alpine"}
        """

    private static let process = """
        {"arguments": [], "environment": [], "executable": "/bin/sh", "rlimits": [], "supplementalGroups": [],
         "terminal": false, "user": {"id": {"gid": 0, "uid": 0}}, "workingDirectory": "/"}
        """

    private static let volume = """
        {"creationDate": 800000000, "driver": "local", "format": "ext4",
         "labels": {"com.apple.container.resource.anonymous": ""}, "name": "data", "options": {},
         "sizeInBytes": 1000000, "source": "/tmp/v/volume.img"}
        """

    private static let kernel = """
        {"commandLine": {"initArgs": [], "kernelArgs": ["console=hvc0", "tsc=reliable", "panic=0"]},
         "path": "file:///tmp/c/kernel.bin", "platform": {"architecture": "arm64", "os": "linux"}}
        """

    private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    /// Encodes `value` and reads it back as plain JSON objects, to look at its shape.
    private func shape(of value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)

        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("Reads a container configuration the CLI wrote")
    func readsCLIContainerConfiguration() throws {
        let configuration = try decode(ContainerConfiguration.self, from: Self.containerConfiguration)

        #expect(configuration.id == "web")
        #expect(configuration.image.reference == "docker.io/library/alpine:latest")
        #expect(configuration.initProcess.user == .raw(userString: "nobody"))
        #expect(configuration.mounts.map(\.destination) == ["/a", "/data", "/share", "/tmp"])
        #expect(configuration.mounts[1].volumeName == "data")
        #expect(configuration.mounts[0].type == .block(format: "ext4", cache: .on, sync: .fsync))
        #expect(configuration.publishedSockets.first?.hostPath.path == "/tmp/a.sock")
        #expect(configuration.capAdd == ["CAP_NET_ADMIN"])
        #expect(configuration.capDrop == ["CAP_SYS_ADMIN"])
        #expect(configuration.resources.cpus == 2)
        #expect(configuration.resources.cpuOverhead == 1)
        #expect(configuration.runtimeHandler == "container-runtime-linux")
        #expect(configuration.maskedPaths == ["/proc/kcore"])
        #expect(configuration.readonlyPaths == [])
        #expect(configuration.networks.first?.options.aliases == ["api.example.test"])
        #expect(configuration.networks.first?.options.mtu == 1400)
        #expect(configuration.readOnly)
    }

    @Test("Fills in what an older configuration leaves out as the CLI does")
    func readsSparseConfiguration() throws {
        let json = #"{"id": "old", "image": \#(Self.image), "initProcess": \#(Self.process), "resources": {"cpus": 3}}"#
        let configuration = try decode(ContainerConfiguration.self, from: json)

        #expect(configuration.resources.cpus == 3)
        #expect(configuration.resources.memoryInBytes == 1024 * 1024 * 1024)
        #expect(configuration.resources.cpuOverhead == 1)
        #expect(configuration.runtimeHandler == "container-runtime-linux")
        #expect(configuration.maskedPaths == nil)
    }

    @Test("Writes an attachment without aliases as the CLI does")
    func writesAttachmentWithoutAliases() throws {
        let written = try shape(of: AttachmentOptions(hostname: "web"))

        #expect(written.keys.sorted() == ["hostname"])
    }

    @Test("Completes a bundle the CLI created but never started")
    func completesCLIBundle() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        for name in ["kernel-source.bin", "init.ext4", "snapshot.ext4"] {
            try Data(name.utf8).write(to: directory.appending(name))
        }

        let configuration = try decode(ContainerConfiguration.self, from: Self.containerConfiguration)
        var kernel = try decode(Kernel.self, from: Self.kernel)
        kernel.path = directory.appending("kernel-source.bin")

        let path = directory.appending("containers/web")
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)

        let bundle = Bundle(path: path)
        try bundle.write(
            filename: "runtime-configuration.json",
            value: Bundle.RuntimeConfiguration(
                initialFilesystem: .block(source: directory.appending("init.ext4").path, destination: "/", options: ["ro"]),
                kernel: kernel,
                containerConfiguration: configuration,
                containerRootFilesystem: .block(source: directory.appending("snapshot.ext4").path, destination: "/"),
                options: ContainerCreateOptions(autoRemove: false)
            )
        )

        #expect(try bundle.storedConfiguration.id == "web")
        #expect((try? bundle.configuration) == nil)

        try bundle.completeFromRuntimeConfiguration()

        #expect(try bundle.configuration.id == "web")
        #expect(try bundle.kernel.path == path.appendingPathComponent("kernel.bin"))
        #expect(try bundle.containerRootfs.options == ["ro"])

        for name in ["kernel.bin", "initfs.ext4", "rootfs.ext4", "options.json"] {
            #expect(FileManager.default.fileExists(atPath: path.appendingPathComponent(name).path), "\(name) is missing")
        }
    }

    @Test("Writes a container configuration the CLI can read back")
    func writesCLIContainerConfiguration() throws {
        let configuration = try decode(ContainerConfiguration.self, from: Self.containerConfiguration)
        let written = try shape(of: configuration)

        // What the app writes decodes as the CLI's own, so it must match the CLI's fixture.
        let cli = try #require(
            JSONSerialization.jsonObject(with: Data(Self.containerConfiguration.utf8)) as? [String: Any]
        )

        for key in [
            "mounts", "publishedSockets", "publishedPorts", "initProcess", "image", "networks", "dns", "capAdd", "capDrop",
            "resources", "runtimeHandler", "maskedPaths", "readonlyPaths",
        ] {
            // Wrapped, since a value such as a string can't be written on its own.
            let writtenValue = try JSONSerialization.data(withJSONObject: [try #require(written[key])], options: .sortedKeys)
            let cliValue = try JSONSerialization.data(withJSONObject: [try #require(cli[key])], options: .sortedKeys)

            #expect(writtenValue == cliValue, "\(key) differs from what the CLI writes")
        }
    }

    @Test("Writes a block filesystem with the CLI's cache and sync modes")
    func writesBlockFilesystem() throws {
        let filesystem = Filesystem.block(source: "/tmp/c/rootfs.ext4", destination: "/")
        let type = try #require(try shape(of: filesystem)["type"] as? [String: Any])
        let block = try #require(type["block"] as? [String: Any])

        #expect((block["cache"] as? [String: Any])?.keys.first == "on")
        #expect((block["sync"] as? [String: Any])?.keys.first == "fsync")
    }

    @Test("Reads and writes a volume as the CLI does")
    func readsAndWritesCLIVolume() throws {
        let volume = try decode(Volume.self, from: Self.volume)

        #expect(volume.name == "data")
        #expect(volume.isAnonymous)
        #expect(volume.creationDate == Date(timeIntervalSinceReferenceDate: 800_000_000))

        let written = try shape(of: volume)

        #expect(written["creationDate"] as? Double == 800_000_000)
        #expect(written["createdAt"] == nil)
    }

    @Test("Reads a volume written before the CLI's 1.0")
    func readsLegacyCLIVolume() throws {
        let json = #"{"name": "old", "driver": "local", "format": "ext4", "source": "/v", "createdAt": 1000}"#
        let volume = try decode(Volume.self, from: json)

        #expect(volume.creationDate == Date(timeIntervalSinceReferenceDate: 1000))
    }

    @Test("Reads a kernel the CLI wrote")
    func readsCLIKernel() throws {
        let kernel = try decode(Kernel.self, from: Self.kernel)

        #expect(kernel.path.path == "/tmp/c/kernel.bin")
        #expect(kernel.platform.architecture == .arm64)
    }

    @Test("Reads the CLI's settings from its folder, with its defaults for the rest")
    func readsSystemConfiguration() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        try directory.write(
            """
            [kernel]
            url = "https://example.com/kernel.tar.zst"

            [container]
            cpus = 8
            memory = "4g"

            [build]
            memory = "2048MB"
            rosetta = false

            [dns]
            domain = "test"

            [registry]
            domain = "registry.example.com"

            [vminit]
            image = "ghcr.io/example/vminit:custom"
            """,
            to: "config/config.toml"
        )

        let configuration = await SystemConfiguration.load(appRoot: directory.url, includingInstallDefaults: false)

        #expect(configuration.kernelURL == "https://example.com/kernel.tar.zst")
        #expect(configuration.kernelDigest == nil)
        #expect(configuration.kernelBinaryPath == SystemConfiguration.defaults.kernelBinaryPath)
        #expect(configuration.containerCPUs == 8)
        #expect(configuration.containerMemoryInBytes == 4 * 1024 * 1024 * 1024)
        #expect(configuration.buildMemoryInBytes == 2048 * 1024 * 1024)
        #expect(configuration.buildCPUs == SystemConfiguration.defaults.buildCPUs)
        #expect(!configuration.buildRosetta)
        #expect(configuration.dnsDomain == "test")
        #expect(configuration.registryDomain == "registry.example.com")
        #expect(configuration.initImage == "ghcr.io/example/vminit:custom")
        #expect(configuration.builderImage == SystemConfiguration.defaults.builderImage)
    }

    @Test("Without a config.toml, the CLI's own defaults apply")
    func usesCLIDefaults() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let configuration = await SystemConfiguration.load(files: [directory.appending("config/config.toml")])

        #expect(configuration == SystemConfiguration.defaults)
        #expect(configuration.containerCPUs == 4)
        #expect(configuration.containerMemoryInBytes == 1024 * 1024 * 1024)
    }

    @Test("Writes only what differs from the CLI's defaults, in a file the CLI reads back the same")
    func writesConfiguration() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        var configuration = SystemConfiguration.defaults
        configuration.containerCPUs = 6
        configuration.buildMemoryInBytes = 3 * 1024 * 1024 * 1024
        configuration.dnsDomain = "my \"lab\""

        try configuration.write(to: directory.url)

        let text = try String(contentsOf: directory.appending("config/config.toml"), encoding: .utf8)

        #expect(!text.contains("[kernel]"))
        #expect(text.contains("[container]\ncpus = 6"))
        #expect(await SystemConfiguration.load(appRoot: directory.url, includingInstallDefaults: false) == configuration)

        try SystemConfiguration.defaults.write(to: directory.url)

        #expect(!FileManager.default.fileExists(atPath: directory.appending("config/config.toml").path))
    }

    @Test("Checks a kernel archive against its digest, as the CLI does")
    func verifiesKernelDigest() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let archive = directory.url.appending(path: "kernel.tar.zst")
        try Data("hello".utf8).write(to: archive)

        try KernelService.verifyDigest(of: archive, expected: "sha256:2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        try KernelService.verifyDigest(of: archive, expected: "SHA256:2CF24DBA5FB0A30E26E83B2AC5B9E29E1B161E5C1FA7425E73043362938B9824")

        #expect(throws: (any Error).self) {
            try KernelService.verifyDigest(of: archive, expected: "sha256:\(String(repeating: "0", count: 64))")
        }
        #expect(throws: (any Error).self) {
            try KernelService.verifyDigest(of: archive, expected: "md5:5d41402abc4b2a76b9719d911017c592")
        }
    }

    @Test("Volume store reads the CLI's entity folders")
    func volumeStoreReadsCLIEntities() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        try directory.write(Self.volume, to: "data/entity.json")

        let store = try FilesystemEntityStore<Volume>(path: directory.url, type: "volumes", log: .init(label: "test"))
        let volumes = try await store.list()

        #expect(volumes.map(\.name) == ["data"])
    }
}
