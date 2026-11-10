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
    private let containerSystem: ContainerSystem
    private let logger: Logger

    static let builderContainerId = Builder.builderContainerId

    init() {
        self.containerSystem = ContainerSystem.shared
        var logger = Logger(label: "app.containers.builder.controller")
        logger.logLevel = .info
        self.logger = logger
    }

    #if DEBUG
    /// Internal initializer for testing - allows injection of a test container system
    init(testSystem: ContainerSystem) {
        self.containerSystem = testSystem
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

        let containerService = try containerSystem.containerService
        let imageService = try containerSystem.imageService
        let kernelService = try containerSystem.kernelService

        guard let appRoot = containerSystem.appRoot else {
            throw ContainerSystem.notRunningError
        }

        let builderImage: String = DefaultsStore.get(key: .defaultBuilderImage)
        let exportsMount: String = appRoot.appendingPathComponent("builder").path

        if !FileManager.default.fileExists(atPath: exportsMount) {
            try FileManager.default.createDirectory(
                atPath: exportsMount,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        let builderPlatform = ContainerizationOCI.Platform(arch: "arm64", os: "linux", variant: "v8")

        // Check if builder container already exists
        let containerList = await containerService.list()
        let existingContainer = containerList.first(where: {
            $0.configuration.id == Self.builderContainerId
        })

        if let existingContainer {
            logger.info("Found existing builder container, cleaning it up to ensure fresh start")
            if existingContainer.status == .running {
                do {
                    try await containerService.stop(id: Self.builderContainerId, options: .default)
                } catch {
                    logger.warning("Failed to stop existing builder, proceeding with delete: \(error)")
                }
            }
            do {
                try await containerService.delete(id: Self.builderContainerId)
            } catch {
                logger.warning("Failed to delete existing builder, continuing anyway: \(error)")
            }
        }

        let useRosetta = DefaultsStore.getBool(key: .buildRosetta) ?? true
        // Without Rosetta, the shim builds other architectures with QEMU.
        let shimArguments = ["--debug", "--vsock"] + (useRosetta ? [] : ["--enable-qemu"])

        try validEntityName(Self.builderContainerId)

        var resources = ContainerConfiguration.Resources()
        resources.cpus = Int(cpus)
        resources.memoryInBytes = memory

        logger.info("Pulling builder image: \(builderImage)")

        let progress = progress ?? Progress(parent: nil)
        progress.totalUnitCount = 3

        let imageDescription = try await progress.performStep("Fetching builder image") { step in
            try await imageService.pull(
                reference: builderImage,
                platform: builderPlatform,
                insecure: false,
                progressUpdate: step.updateHandler()
            )
        }

        logger.info("Unpacking builder image")

        try await progress.performStep("Unpacking builder image") { step in
            try await imageService.unpack(
                description: imageDescription,
                platform: builderPlatform,
                progressUpdate: step.updateHandler()
            )
        }

        let processConfig = ProcessConfiguration(
            executable: "/usr/local/bin/container-builder-shim",
            arguments: shimArguments,
            environment: try await imageService.environment(of: imageDescription, platform: builderPlatform),
            workingDirectory: "/",
            terminal: false,
            user: .id(uid: 0, gid: 0)
        )

        var config = ContainerConfiguration(
            id: Self.builderContainerId,
            image: imageDescription,
            process: processConfig
        )
        config.resources = resources
        config.labels = [
            "com.apple.container.plugin": "builder",
            "com.apple.container.resource.role": "builder",
        ]
        config.capAdd = ["ALL"]
        config.mounts = [
            .init(type: .tmpfs, source: "", destination: "/run", options: []),
            .init(
                type: .virtiofs,
                source: exportsMount,
                destination: "/var/lib/container-builder-shim/exports",
                options: []
            ),
        ]
        config.rosetta = useRosetta

        // Attach to default network (sandboxed mode uses built-in NAT networking with automatic DNS)
        let defaultNetworkName = "default"
        config.networks = [
            AttachmentConfiguration(
                network: defaultNetworkName,
                options: AttachmentOptions(hostname: Self.builderContainerId)
            )
        ]
        // No nameservers, so the network's gateway answers.
        config.dns = ContainerConfiguration.DNSConfiguration(nameservers: [])

        try await progress.performStep("Starting BuildKit") { _ in
            logger.info("Getting kernel")
            let kernel = try await kernelService.getDefaultKernel(platform: .current)

            logger.info("Creating BuildKit container")
            let options = ContainerCreateOptions(autoRemove: false)
            try await containerService.create(configuration: config, kernel: kernel, options: options)

            try await startBuildKitProcess(service: containerService)
        }

        logger.info("Builder started successfully")
    }

    /// Restart the builder container to pick up fresh virtiofs mounts
    /// This is necessary when new subdirectories have been created in mounted paths
    /// because virtiofs in sandboxed apps doesn't dynamically show new subdirectories
    func restart(cpus: Int64 = 2, memory: UInt64 = 1024.mib(), progress: Progress? = nil) async throws {
        logger.info("Restarting builder to pick up fresh mounts")

        let containerService = try containerSystem.containerService

        // Stop the existing builder
        let containerList = await containerService.list()
        let existingContainer = containerList.first(where: {
            $0.configuration.id == Self.builderContainerId
        })

        if let existingContainer {
            if existingContainer.status == .running {
                logger.info("Stopping existing builder")
                do {
                    try await containerService.stop(id: Self.builderContainerId, options: .default)
                } catch {
                    logger.warning("Failed to cleanly stop existing builder, proceeding with delete: \(error)")
                }
            } else {
                logger.info("Deleting existing builder (status: \(existingContainer.status))")
            }

            do {
                try await containerService.delete(id: Self.builderContainerId)
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

    private func startBuildKitProcess(service: any ContainerService) async throws {
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
