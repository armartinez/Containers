//
//  ContainerCLITests.swift
//  ContainersCoreTests
//
//  Working over the container CLI's folder, with CLI compatibility.
//

import ContainerizationError
import Foundation
import Logging
import Testing

@testable import ContainersCore

@Suite("Container CLI")
struct ContainerCLITests {

    @Test("CLI compatibility manages the CLI's folder while its API server is stopped")
    @MainActor
    func cliCompatibilityManagesFolder() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        try writeAPIServerPlist(in: directory.url)

        let containerSystem = MockContainerSystem()
        containerSystem.mode = .cliCompatibility

        try await containerSystem.start(appRoot: directory.url)

        #expect(containerSystem.status == .running)
        #expect(!containerSystem.isReadOnly)

        try await containerSystem.stop()
    }

    @Test("Default mode starts the system by itself")
    @MainActor
    func defaultModeStartsByItself() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let containerSystem = MockContainerSystem()

        try await containerSystem.start(appRoot: directory.url)

        #expect(containerSystem.status == .running)

        try await containerSystem.stop()
    }

    @Test("Reports aren't kept in the CLI's folder")
    @MainActor
    func noReportsWhileReadOnly() async {
        let containerSystem = MockContainerSystem()
        let reportManager = ReportManager(testSystem: containerSystem)

        containerSystem.status = .readOnly

        #expect(!reportManager.isAvailable)

        let report = await reportManager.record(kind: .image, name: "alpine", message: "Pull failed", error: CancellationError())

        #expect(report == nil)
    }

    @Test("Status says the system is read-only beside the CLI")
    @MainActor
    func reportsReadOnlyStatus() {
        let containerSystem = MockContainerSystem()

        containerSystem.status = .readOnly

        #expect(containerSystem.status == .readOnly)
        #expect(containerSystem.isRunning)
        #expect(containerSystem.isReadOnly)
    }

    @Test("A read-only service refuses its changes, and the default one makes them")
    func servicesRefuseChangesWhenReadOnly() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let log = Logger(label: "tests.cli")
        let volumes = DefaultVolumeService(appRoot: directory.url, log: log)
        let readOnlyNetworks: any NetworkService = ReadOnlyNetworkService(appRoot: directory.url, log: log)
        let readOnlyVolumes: any VolumeService = ReadOnlyVolumeService(appRoot: directory.url, log: log)

        await #expect(throws: ContainerCLIError.apiServerRunning) {
            try await readOnlyNetworks.create(try NetworkConfiguration(name: "backend"))
        }
        await #expect(throws: ContainerCLIError.apiServerRunning) {
            try await readOnlyVolumes.create(name: "data", labels: [:], options: [:], sizeInBytes: nil)
        }

        try await DefaultNetworkService(appRoot: directory.url, log: log).create(try NetworkConfiguration(name: "backend"))
        _ = try await volumes.create(name: "data", labels: [:], options: [:], sizeInBytes: 1024 * 1024)
    }

    // MARK: - The CLI's API server

    @Test("Reads a running API server's status and folder")
    func parsesRunningStatus() throws {
        let versions = #"[{"appName":"container","version":"1.6.1"},{"appName":"container-apiserver","version":"1.6.0"}]"#
        let json = #"{"versions":\#(versions),"status":{"status":"running","paths":{"appRoot":"/Users/me/Library/Application Support/com.apple.container/"}}}"#

        let status = try ContainerCLI.Status(output: Data(json.utf8))

        #expect(status.isInstalled)
        #expect(status.isRunning)
        #expect(status.appRoot?.path(percentEncoded: false) == "/Users/me/Library/Application Support/com.apple.container/")
        #expect(status.cliVersion == "1.6.1")
        #expect(status.apiServerVersion == "1.6.0")
    }

    @Test("Reads a stopped API server's status")
    func parsesStoppedStatus() throws {
        let status = try ContainerCLI.Status(output: Data(#"{"versions":[{"appName":"container","version":"1.6.1"}],"status":{"status":"unregistered"}}"#.utf8))

        #expect(status.isInstalled)
        #expect(!status.isRunning)
        #expect(status.appRoot == nil)
        #expect(status.cliVersion == "1.6.1")
        #expect(status.apiServerVersion == nil)
    }

    @Test("An API server registered with launchd but not answering counts as running")
    func parsesRegisteredStatus() throws {
        let status = try ContainerCLI.Status(output: Data(#"{"versions":[{"appName":"container","version":"1.6.1"}],"status":{"status":"not running"}}"#.utf8))

        #expect(status.isInstalled)
        #expect(status.isRunning)
        #expect(status.cliVersion == "1.6.1")
    }

    @Test("Reads the script's report of a Mac without the CLI")
    func parsesNotInstalledStatus() throws {
        let status = try ContainerCLI.Status(output: Data(#"{"versions":[],"status":{"status":"notInstalled"}}"#.utf8))

        #expect(!status.isInstalled)
        #expect(!status.isRunning)
        #expect(status.cliVersion == nil)
    }

    @Test("Refuses output that isn't the CLI's status")
    func rejectsUnknownOutput() {
        #expect(throws: ContainerCLI.StatusError.self) {
            try ContainerCLI.Status(output: Data("command not found".utf8))
        }
    }

    @Test("A folder an API server has started over is the CLI's")
    func recognizesCLIFolder() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        #expect(!ContainerCLI.isAppRoot(directory.url))

        try writeAPIServerPlist(in: directory.url)

        #expect(ContainerCLI.isAppRoot(directory.url))
    }

    @Test("Containers mode doesn't start on a CLI's folder, without asking the CLI")
    @MainActor
    func refusesCLIFolder() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        try writeAPIServerPlist(in: directory.url)

        let containerSystem = MockContainerSystem {
            throw ContainerCLIError.statusScriptNotInstalled
        }

        await #expect(throws: ContainerCLIError.appRootInUse) {
            try await containerSystem.start(appRoot: directory.url)
        }

        #expect(containerSystem.status == .failed)
    }

    @Test("A folder inside a CLI's folder belongs to the CLI, and one around it doesn't")
    func recognizesFoldersInsideCLIFolder() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let cliFolder = directory.url.appending(path: "cli")
        let inner = cliFolder.appending(path: "containers/web")
        let unrelated = directory.url.appending(path: "other")

        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        try writeAPIServerPlist(in: cliFolder)

        #expect(ContainerCLI.owns(cliFolder))
        #expect(ContainerCLI.owns(inner))
        #expect(!ContainerCLI.owns(directory.url))
        #expect(!ContainerCLI.owns(unrelated))
    }

    @Test("Containers mode doesn't start inside a CLI's folder")
    @MainActor
    func refusesFolderInsideCLIFolder() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let inner = directory.url.appending(path: "containers")

        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try writeAPIServerPlist(in: directory.url)

        let containerSystem = MockContainerSystem {
            throw ContainerCLIError.statusScriptNotInstalled
        }

        await #expect(throws: ContainerCLIError.appRootInUse) {
            try await containerSystem.start(appRoot: inner)
        }
    }

    @Test("Containers mode doesn't ask about the API server over a folder of its own")
    @MainActor
    func skipsCheckOverOwnFolder() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let containerSystem = MockContainerSystem {
            throw ContainerCLIError.statusScriptNotInstalled
        }

        try await containerSystem.start(appRoot: directory.url)

        #expect(containerSystem.status == .running)

        try await containerSystem.stop()
    }

    @Test("CLI compatibility starts read-only beside a running API server")
    @MainActor
    func cliCompatibilityStartsBesideAPIServer() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        try writeAPIServerPlist(in: directory.url)

        let appRoot = directory.url
        let containerSystem = MockContainerSystem {
            ContainerCLI.Status(isInstalled: true, isRunning: true, appRoot: appRoot, cliVersion: "1.6.1", apiServerVersion: "1.6.1")
        }
        containerSystem.mode = .cliCompatibility

        try await containerSystem.start(appRoot: appRoot)

        #expect(containerSystem.status == .readOnly)

        try await containerSystem.stop()
    }

    @Test("CLI compatibility needs the status script")
    @MainActor
    func cliCompatibilityNeedsScript() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        try writeAPIServerPlist(in: directory.url)

        let containerSystem = MockContainerSystem {
            throw ContainerCLIError.statusScriptNotInstalled
        }
        containerSystem.mode = .cliCompatibility

        await #expect(throws: ContainerCLIError.statusScriptNotInstalled) {
            try await containerSystem.start(appRoot: directory.url)
        }

        #expect(containerSystem.status == .failed)
    }

    @Test("CLI compatibility needs the CLI installed")
    @MainActor
    func cliCompatibilityNeedsCLI() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        try writeAPIServerPlist(in: directory.url)

        let containerSystem = MockContainerSystem {
            ContainerCLI.Status(isInstalled: false, isRunning: false)
        }
        containerSystem.mode = .cliCompatibility

        await #expect(throws: ContainerCLIError.notInstalled) {
            try await containerSystem.start(appRoot: directory.url)
        }
        await #expect(throws: ContainerCLIError.notInstalled) {
            try await containerSystem.cli.requireInstalled()
        }
    }

    @Test("CLI compatibility refuses a CLI version that isn't supported")
    @MainActor
    func cliCompatibilityRefusesUnsupportedVersion() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        try writeAPIServerPlist(in: directory.url)

        let containerSystem = MockContainerSystem {
            ContainerCLI.Status(isInstalled: true, isRunning: false, cliVersion: "1.7.0")
        }
        containerSystem.mode = .cliCompatibility

        await #expect(throws: ContainerCLIError.unsupportedVersion("1.7.0")) {
            try await containerSystem.start(appRoot: directory.url)
        }
    }

    @Test("An API server still running an unsupported version is refused")
    @MainActor
    func refusesUnsupportedAPIServerVersion() async {
        let containerSystem = MockContainerSystem {
            ContainerCLI.Status(isInstalled: true, isRunning: true, cliVersion: "1.6.1", apiServerVersion: "1.5.0")
        }

        await #expect(throws: ContainerCLIError.unsupportedVersion("1.5.0")) {
            try await containerSystem.cli.requireInstalled()
        }
    }

    @Test("Containers mode stops when a CLI starts on its folder")
    @MainActor
    func stopsWhenAPIServerStarts() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let containerSystem = MockContainerSystem()

        try await containerSystem.start(appRoot: directory.url)

        // FSEvents needs a moment to start reporting.
        try await Task.sleep(for: .milliseconds(500))
        try writeAPIServerPlist(in: directory.url)

        let deadline = ContinuousClock.now + .seconds(5)

        while containerSystem.status != .failed, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(containerSystem.status == .failed)
        #expect(containerSystem.startupError as? ContainerCLIError == .appRootInUse)
    }

    @Test("CLI compatibility switches to read-only when the CLI starts")
    @MainActor
    func cliCompatibilitySwitchesToReadOnly() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        try writeAPIServerPlist(in: directory.url)

        let containerSystem = MockContainerSystem()
        containerSystem.removesAppRootOnStop = false

        containerSystem.mode = .cliCompatibility

        try await containerSystem.start(appRoot: directory.url)

        #expect(containerSystem.status == .running)

        // FSEvents needs a moment to start reporting.
        try await Task.sleep(for: .milliseconds(500))
        try writeAPIServerPlist(in: directory.url)

        let deadline = ContinuousClock.now + .seconds(5)

        while containerSystem.status != .readOnly, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(containerSystem.status == .readOnly)

        try await containerSystem.stop()
    }

    @Test("Stopped with CLI compatibility on, the system starts read-only once the CLI starts")
    @MainActor
    func watchesForAPIServerWhileStopped() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        try writeAPIServerPlist(in: directory.url)

        let containerSystem = MockContainerSystem()
        containerSystem.removesAppRootOnStop = false

        containerSystem.mode = .cliCompatibility

        try await containerSystem.start(appRoot: directory.url)
        try await containerSystem.stop()

        #expect(containerSystem.status == .notStarted)

        // FSEvents needs a moment to start reporting.
        try await Task.sleep(for: .milliseconds(500))
        try writeAPIServerPlist(in: directory.url)

        let deadline = ContinuousClock.now + .seconds(5)

        while containerSystem.status != .readOnly, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(containerSystem.status == .readOnly)

        try await containerSystem.stop()
    }

    @Test("CLI compatibility doesn't start over a folder that isn't the CLI's")
    @MainActor
    func cliCompatibilityRefusesOwnFolder() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let containerSystem = MockContainerSystem()
        containerSystem.mode = .cliCompatibility

        await #expect(throws: ContainerCLIError.notAppRoot) {
            try await containerSystem.start(appRoot: directory.url)
        }

        #expect(containerSystem.status == .failed)
    }

    @Test("Images aren't pulled, built, loaded or deleted while read-only")
    @MainActor
    func refusesImageWritesWhileReadOnly() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let containerSystem = try await startReadOnlySystem(in: directory)
        let imageManager = ImageManager(testSystem: containerSystem)
        let folder = directory.url
        let image = try JSONDecoder().decode(ImageDescription.self, from: Data(Self.imageJSON.utf8))

        await #expect(throws: ContainerCLIError.apiServerRunning) {
            try await imageManager.pull(reference: "alpine")
        }
        await #expect(throws: ContainerCLIError.apiServerRunning) {
            try await imageManager.build(dockerFile: folder.appending(path: "Dockerfile"), contextDirectory: folder, tag: "web")
        }
        await #expect(throws: ContainerCLIError.apiServerRunning) {
            try await imageManager.load(tar: folder)
        }
        await #expect(throws: ContainerCLIError.apiServerRunning) {
            try await imageManager.delete(images: [image])
        }
    }

    @Test("Containers aren't created, run, stopped, deleted or exec'd into while read-only")
    @MainActor
    func refusesContainerChangesWhileReadOnly() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let containerSystem = try await startReadOnlySystem(in: directory)
        let containerManager = ContainerManager(testSystem: containerSystem)
        let json = #"{"id": "web", "image": \#(Self.imageJSON), "initProcess": \#(Self.processJSON)}"#
        let configuration = try JSONDecoder().decode(ContainerConfiguration.self, from: Data(json.utf8))

        await #expect(throws: ContainerCLIError.apiServerRunning) {
            try await containerManager.create(
                imageReference: "alpine",
                arguments: [],
                process: ContainerProcess(),
                configuration: configuration,
                options: ContainerManagementOptions()
            )
        }
        await #expect(throws: ContainerCLIError.apiServerRunning) {
            try await containerManager.run(id: "web")
        }
        await #expect(throws: ContainerCLIError.apiServerRunning) {
            try await containerManager.exec(id: "web", arguments: ["true"])
        }
        await #expect(throws: ContainerCLIError.apiServerRunning) {
            try await containerManager.stop(ids: ["web"], timeoutSeconds: 1)
        }

        let bundle = Bundle(path: directory.url.appending(path: "containers/web"))

        try FileManager.default.createDirectory(at: bundle.path, withIntermediateDirectories: true)
        try bundle.write(filename: "config.json", value: configuration)
        await containerSystem.reloadSharedContainers()

        await #expect(throws: ContainerCLIError.apiServerRunning) {
            try await containerManager.delete(ids: ["web"], force: false)
        }
    }

    @Test("Networks and volumes aren't created or deleted while read-only")
    @MainActor
    func refusesNetworkAndVolumeChangesWhileReadOnly() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let containerSystem = try await startReadOnlySystem(in: directory)
        let networkManager = NetworkManager(testSystem: containerSystem)
        let volumeManager = VolumeManager(testSystem: containerSystem)
        let volume = Volume(name: "data", driver: "local", format: "ext4", source: "/nonexistent", labels: [:], options: [:], sizeInBytes: 1024 * 1024)

        await #expect(throws: ContainerCLIError.apiServerRunning) {
            try await networkManager.createNetwork(name: "backend")
        }
        await #expect(throws: ContainerCLIError.apiServerRunning) {
            try await networkManager.deleteNetwork(named: "backend")
        }
        await #expect(throws: ContainerCLIError.apiServerRunning) {
            try await volumeManager.create(name: "data", labels: [], options: [], sizeInBytes: nil)
        }
        await #expect(throws: ContainerCLIError.apiServerRunning) {
            try await volumeManager.delete(volumes: [volume])
        }
    }

    private static let imageJSON = """
        {"descriptor": {"digest": "sha256:\(String(repeating: "a", count: 64))",
         "mediaType": "application/vnd.oci.image.index.v1+json", "size": 1}, "reference": "alpine"}
        """

    private static let processJSON = """
        {"arguments": [], "environment": [], "executable": "/bin/sh", "rlimits": [], "supplementalGroups": [],
         "terminal": false, "user": {"id": {"gid": 0, "uid": 0}}, "workingDirectory": "/"}
        """

    /// A system running beside the CLI's API server, whose services were built read-only.
    @MainActor
    private func startReadOnlySystem(in directory: TemporaryDirectory) async throws -> MockContainerSystem {
        let containerSystem = MockContainerSystem()
        containerSystem.removesAppRootOnStop = false

        try await containerSystem.launch(appRoot: directory.url, readOnly: true, installingKernel: false)

        return containerSystem
    }

    private func writeAPIServerPlist(in folder: URL) throws {
        let plist = folder.appending(path: "apiserver/apiserver.plist")

        try FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("<plist/>".utf8).write(to: plist)
    }
}
