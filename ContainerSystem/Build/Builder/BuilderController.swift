//
//  BuilderController.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import Containerization
import ContainerizationError
import ContainerizationExtras
import ContainerizationOCI
import ContainerizationOS
import Foundation
import Logging

/// Coordinates the BuildKit builder container lifecycle.
@MainActor
final class BuilderController {
    private let runtime: ContainerRuntime
    private let logger: Logger

    static let builderContainerId = Builder.builderContainerId

    init() {
        self.runtime = ContainerRuntime.shared
        var logger = Logger(label: "app.containers.builder.controller")
        logger.logLevel = .info
        self.logger = logger
    }

    #if DEBUG
    /// Internal initializer for testing - allows injection of test runtime
    init(testRuntime: ContainerRuntime) {
        self.runtime = testRuntime
        var logger = Logger(label: "app.containers.builder.controller.test")
        logger.logLevel = .debug
        self.logger = logger
    }
    #endif

    // MARK: - Internal API

    /// Start the BuildKit builder container
    /// This method is idempotent - if builder is already running, it will restart it to ensure fresh mounts
    func start(cpus: Int64 = 2, memory: UInt64 = 1024.mib(), progress: Progress? = nil) async throws {
        logger.info("Starting builder with cpus=\(cpus), memory=\(memory)")

        let containersService = try await runtime.getContainersService()
        let imagesService = try await runtime.getImagesService()
        let kernelService = try await runtime.getKernelService()
        let appRoot = try runtime.getAppRoot()

        let builderImage: String = DefaultsStore.get(key: .defaultBuilderImage)
        let exportsMount: String = appRoot.appendingPathComponent(".build").path

        if !FileManager.default.fileExists(atPath: exportsMount) {
            try FileManager.default.createDirectory(
                atPath: exportsMount,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        // Content store path needs to be accessible by builder for image operations
        let imagesPath = appRoot.appendingPathComponent("images").path

        // BuildKit data directory - needs to be persistent and support mmap for BoltDB
        let buildkitDataPath = appRoot.appendingPathComponent("buildkit-data")
            .path

        // Check if BoltDB database exists and might be corrupted
        // If BuildKit previously crashed, the database can be in a bad state
        let workerDbPath = (buildkitDataPath as NSString)
            .appendingPathComponent("worker.db")
        if FileManager.default.fileExists(atPath: workerDbPath) {
            logger.info("Found existing BuildKit database, checking if it needs cleanup")
            // For now, always delete and recreate to avoid corruption issues
            // In the future, we could try to validate the database first
            try? FileManager.default.removeItem(atPath: buildkitDataPath)
            logger.info("Cleaned up BuildKit data directory")
        }

        if !FileManager.default.fileExists(atPath: buildkitDataPath) {
            try FileManager.default.createDirectory(
                atPath: buildkitDataPath,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        let builderPlatform = ContainerizationOCI.Platform(arch: "arm64", os: "linux", variant: "v8")

        // Check if builder container already exists
        let containerList = await containersService.list()
        let existingContainer = containerList.first(where: {
            $0.configuration.id == Self.builderContainerId
        })

        if let existingContainer {
            logger.info("Found existing builder container, cleaning it up to ensure fresh start")
            if existingContainer.status == .running {
                do {
                    try await containersService.stop(id: Self.builderContainerId, options: .default)
                } catch {
                    logger.warning("Failed to stop existing builder, proceeding with delete: \(error)")
                }
            }
            do {
                try await containersService.delete(id: Self.builderContainerId)
            } catch {
                logger.warning("Failed to delete existing builder, continuing anyway: \(error)")
            }
        }

        let shimArguments: [String] = ["--debug", "--vsock"]

        try validEntityName(Self.builderContainerId)

        let processConfig = ProcessConfiguration(
            executable: "/usr/local/bin/container-builder-shim",
            arguments: shimArguments,
            environment: [],
            workingDirectory: "/",
            terminal: false,
            user: .id(uid: 0, gid: 0)
        )

        var resources = ContainerConfiguration.Resources()
        resources.cpus = Int(cpus)
        resources.memoryInBytes = memory

        logger.info("Pulling builder image: \(builderImage)")

        let progress = progress ?? Progress(parent: nil)
        progress.totalUnitCount = 3

        let imageDescription = try await progress.performStep("Fetching builder image") { step in
            try await imagesService.pull(
                reference: builderImage,
                platform: builderPlatform,
                insecure: false,
                progressUpdate: step.updateHandler()
            )
        }

        logger.info("Unpacking builder image")

        try await progress.performStep("Unpacking builder image") { step in
            try await imagesService.unpack(
                description: imageDescription,
                platform: builderPlatform,
                progressUpdate: step.updateHandler()
            )
        }

        var config = ContainerConfiguration(
            id: Self.builderContainerId,
            image: imageDescription,
            process: processConfig
        )
        config.resources = resources
        config.capabilities = ["ALL"]
        config.mounts = [
            .init(type: .tmpfs, source: "", destination: "/run", options: []),
            .init(
                type: .virtiofs,
                source: exportsMount,
                destination: "/var/lib/container-builder-shim/exports",
                options: []
            ),
            .init(type: .virtiofs, source: imagesPath, destination: imagesPath, options: []),
            // Use tmpfs for BuildKit data directory because virtiofs doesn't support mmap
            // which BoltDB requires. This means BuildKit state is ephemeral (lost on restart)
            // but that's acceptable for a build cache.
            // However, we need BuildKit to be able to access our content store for images
            .init(type: .tmpfs, source: "", destination: "/var/lib/buildkit", options: []),
        ]
        // Enable Rosetta only if the user didn't ask to disable it
        config.rosetta = DefaultsStore.getBool(key: .buildRosetta) ?? true

        // Attach to default network (sandboxed mode uses built-in NAT networking with automatic DNS)
        let defaultNetworkName = "default"
        config.networks = [
            AttachmentConfiguration(
                network: defaultNetworkName,
                options: AttachmentOptions(hostname: Self.builderContainerId)
            )
        ]
        config.dns = ContainerConfiguration.DNSConfiguration()

        try await progress.performStep("Starting BuildKit") { _ in
            logger.info("Getting kernel")
            let kernel = try await kernelService.getDefaultKernel(platform: .current)

            logger.info("Creating BuildKit container")
            let options = ContainerCreateOptions(autoRemove: false)
            try await containersService.create(configuration: config, kernel: kernel, options: options)

            try await startBuildKitProcess(service: containersService)
        }

        logger.info("Builder started successfully")
    }

    /// Restart the builder container to pick up fresh virtiofs mounts
    /// This is necessary when new subdirectories have been created in mounted paths
    /// because virtiofs in sandboxed apps doesn't dynamically show new subdirectories
    func restart(cpus: Int64 = 2, memory: UInt64 = 1024.mib(), progress: Progress? = nil) async throws {
        logger.info("Restarting builder to pick up fresh mounts")

        let containersService = try await runtime.getContainersService()

        // Stop the existing builder
        let containerList = await containersService.list()
        let existingContainer = containerList.first(where: {
            $0.configuration.id == Self.builderContainerId
        })

        if let existingContainer {
            if existingContainer.status == .running {
                logger.info("Stopping existing builder")
                do {
                    try await containersService.stop(id: Self.builderContainerId, options: .default)
                } catch {
                    logger.warning("Failed to cleanly stop existing builder, proceeding with delete: \(error)")
                }
            } else {
                logger.info("Deleting existing builder (status: \(existingContainer.status))")
            }

            do {
                try await containersService.delete(id: Self.builderContainerId)
            } catch {
                logger.warning("Failed to delete existing builder cleanly, continuing anyway: \(error)")
            }
        }

        // Start a fresh builder with the new mounts
        try await start(cpus: cpus, memory: memory, progress: progress)
    }

    // MARK: - Private Methods

    /// Validate that a name is a valid entity name.
    @discardableResult
    private func validEntityName(_ name: String) throws -> Bool {
        guard !name.isEmpty, name.count <= 255 else {
            throw ContainerizationError(
                .invalidArgument,
                message: "invalid entity name '\(name)': must be between 1 and 255 characters"
            )
        }

        let entityNamePattern = "^[A-Za-z0-9][A-Za-z0-9_.-]*$"
        let regex = try NSRegularExpression(pattern: entityNamePattern)
        let range = NSRange(name.startIndex..., in: name)

        guard regex.firstMatch(in: name, range: range) != nil else {
            throw ContainerizationError(
                .invalidArgument,
                message: "invalid entity name '\(name)': must match \(entityNamePattern)"
            )
        }

        return true
    }

    private func startBuildKitProcess(service: ContainersService) async throws {
        do {
            logger.info("Bootstrapping BuildKit container")

            // Create pipes to capture BuildKit's stdout/stderr for debugging
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            try await service.bootstrap(
                id: Self.builderContainerId,
                stdio: [nil, stdoutPipe.fileHandleForWriting, stderrPipe.fileHandleForWriting]
            )

            logger.info("Starting BuildKit process")

            logOutput(of: stdoutPipe, named: "stdout", at: .info)
            logOutput(of: stderrPipe, named: "stderr", at: .error)

            try await service.startProcess(id: Self.builderContainerId, processID: Self.builderContainerId)

            logger.info("BuildKit process started successfully")
        } catch {
            logger.error("Failed to start BuildKit: \(error)")

            try? await service.stop(id: Self.builderContainerId, options: .default)

            try? await service.delete(id: Self.builderContainerId)

            if error is ContainerizationError {
                throw error
            }

            throw ContainerizationError(.internalError, message: "failed to start BuildKit: \(error)")
        }
    }

    /// Logs what BuildKit writes to a pipe, line by line, until it closes. A
    /// pipe that fails to read only ends the logging, never the build.
    private func logOutput(of pipe: Pipe, named stream: String, at level: Logger.Level) {
        let logger = logger

        Task {
            do {
                for try await line in pipe.fileHandleForReading.bytes.lines {
                    logger.log(level: level, "BuildKit \(stream): \(line)")
                }
            } catch {
                logger.warning("Stopped reading BuildKit \(stream): \(error)")
            }
        }
    }
}
