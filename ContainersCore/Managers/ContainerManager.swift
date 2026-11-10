//
//  ContainerManager.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import Containerization
import ContainerizationError
import ContainerizationOCI
import ContainerizationOS
import Foundation
import Logging

/// A manager that creates, runs, stops and deletes containers.
///
/// Methods that work on one container take its `id`. Containers the container system runs for itself,
/// such as the builder, are left out of ``list()``.
@Observable
@MainActor
public final class ContainerManager {
    let containerSystem: ContainerSystem

    private let logger: Logger
    private static let internalContainerIDs: Set<String> = ["buildkit"]

    /// The time a container last changed state, such as when it started or stopped.
    ///
    /// Observe this property to refresh a list of containers when one of them changes.
    public var lastContainerChange: Date {
        containerSystem.lastContainerStateChange
    }

    /// Creates a manager for the shared container system.
    public init() {
        self.containerSystem = ContainerSystem.shared
        var logger = Logger(label: "app.containers.manager.container")
        logger.logLevel = .info
        self.logger = logger
    }

    #if DEBUG
    /// Creates a manager over the given container system, so tests can use one of their own.
    init(testSystem: ContainerSystem) {
        self.containerSystem = testSystem
        var logger = Logger(label: "app.containers.manager.container.test")
        logger.logLevel = .debug
        self.logger = logger
    }
    #endif

    // MARK: - Public API

    /// Creates a container from an image, pulling and unpacking the image first if needed.
    ///
    /// - Parameters:
    ///   - imageReference: The image to create the container from.
    ///   - arguments: Arguments to pass to the container's process, after its entry point.
    ///   - process: How to run the container's process, such as its environment and working directory.
    ///   - configuration: The container's resources, mounts, ports and other settings.
    ///   - options: Options for managing the container, such as its name and whether to delete it when it stops.
    ///   - registryScheme: The scheme to reach the image's registry with.
    ///   - progress: A progress that follows the work, step by step, or `nil` to not follow it.
    /// - Returns: The container's ID.
    /// - Throws: ``ContainerCLIError/apiServerRunning`` while the system is read-only, or an error if a container with the same ID exists or the container can't be created.
    @discardableResult
    public func create(
        imageReference: String,
        arguments: [KeyValue],
        process: ContainerProcess,
        configuration: ContainerConfiguration,
        options: ContainerManagementOptions,
        registryScheme: String = RequestScheme.auto.rawValue,
        progress: Progress? = nil
    ) async throws -> String {
        let service = try containerSystem.containerService
        let containerID = try Self.createContainerID(name: options.name)

        logger.info("Creating container", metadata: ["id": "\(containerID)", "image": "\(imageReference)"])

        let existingContainers = await service.list()

        guard
            !existingContainers.contains(where: {
                $0.configuration.id == containerID
            })
        else {
            logger.error("Container \(containerID) already exists")
            throw ContainerizationError(.exists, message: "container already exists: \(containerID)")
        }

        let progress = progress ?? Progress(parent: nil)
        progress.totalUnitCount = 6

        let (configuration, kernel) = try await progress.performStep(pendingUnitCount: 5) { step in
            try await createContainerConfig(
                id: containerID,
                imageReference: imageReference,
                arguments: arguments.map { "\($0.key)=\($0.value)" },
                process: process,
                configuration: configuration,
                options: options,
                registryScheme: registryScheme,
                progress: step
            )
        }

        try Task.checkCancellation()

        try await progress.performStep("Creating container") { _ in
            try await service.create(
                configuration: configuration,
                kernel: kernel,
                options: ContainerCreateOptions(autoRemove: options.deleteOnTermination)
            )
        }

        if Task.isCancelled {
            try? await service.delete(id: configuration.id)
            throw CancellationError()
        }

        if !options.cidfile.isEmpty {
            try writeCIDFile(path: options.cidfile, id: configuration.id)
        }

        return configuration.id
    }

    /// Starts a container.
    ///
    /// - Parameters:
    ///   - id: The container's ID.
    ///   - detach: Whether to return as soon as the container starts, rather than wait for it to exit.
    ///   - progress: A progress that follows the work, step by step, or `nil` to not follow it.
    /// - Returns: The container's exit code, or `nil` if `detach` is `true`.
    /// - Throws: ``ContainerCLIError/apiServerRunning`` while the system is read-only, or an error if the container can't start. A container that fails to start is stopped.
    @discardableResult
    public func run(id: String, detach: Bool = true, progress: Progress? = nil) async throws -> Int32? {
        logger.info("Starting container", metadata: ["id": "\(id)"])
        progress?.localizedDescription = "Starting container"
        let service = try containerSystem.containerService

        do {
            try await service.bootstrap(id: id, stdio: [nil, nil, nil])
            try await service.startProcess(id: id, processID: id)
        } catch {
            try? await service.stop(id: id, options: .default)

            logger.error("Failed to start container \(id): \(error)")

            if error is ContainerizationError || error is ContainerCLIError {
                throw error
            }

            throw ContainerizationError(.internalError, message: "failed to start container: \(error)")
        }

        guard !detach else {
            return nil
        }

        return try await service.wait(id: id)
    }

    /// Returns the memory and CPU time each running container uses, or an empty array if the system isn't running.
    public func resourceUsage() async -> [ContainerResourceUsage] {
        guard let service = try? containerSystem.containerService else {
            return []
        }

        return await service.resourceUsage()
    }

    /// Returns every container, except the ones the container system uses itself, such as the builder.
    public func list() async throws -> [ContainerSnapshot] {
        let service = try containerSystem.containerService

        return await service.list().filter { snapshot in
            !Self.internalContainerIDs.contains(snapshot.configuration.id)
        }
    }

    /// Returns a container.
    ///
    /// - Parameter id: The container's ID.
    /// - Returns: The container.
    /// - Throws: An error if there's no container with that ID.
    public func get(id: String) async throws -> ContainerSnapshot {
        let service = try containerSystem.containerService
        let snapshots = await service.list()

        guard
            let snapshot = snapshots.first(where: { $0.configuration.id == id })
        else {
            throw ContainerizationError(.notFound, message: "Container not found: \(id)")
        }

        return snapshot
    }

    /// Runs a command in a running container and returns its output.
    ///
    /// - Parameters:
    ///   - id: The container's ID.
    ///   - arguments: The command and its arguments.
    /// - Returns: What the command writes to its standard output.
    /// - Throws: ``ContainerCLIError/apiServerRunning`` while the system is read-only, or an error if the container isn't running or the command can't run.
    public func exec(id: String, arguments: [String]) async throws -> String {
        let service = try containerSystem.containerService
        return try await service.exec(id: id, arguments: arguments)
    }

    /// Stops containers, giving each one's process time to exit before forcing it.
    ///
    /// - Parameters:
    ///   - ids: The IDs of the containers to stop.
    ///   - timeoutSeconds: How long to wait for each process to exit after sending it `SIGTERM`.
    /// - Throws: ``ContainerCLIError/apiServerRunning`` while the system is read-only, or an error that lists each container that couldn't be stopped.
    public func stop(ids: [String], timeoutSeconds: Int32) async throws {
        let service = try containerSystem.containerService
        let stopOptions = ContainerStopOptions(timeoutInSeconds: timeoutSeconds, signal: SIGTERM)

        var failed: [(String, Error)] = []

        for id in ids {
            do {
                try await service.stop(id: id, options: stopOptions)
            } catch ContainerCLIError.apiServerRunning {
                // Refused for the whole system, so for every one of them.
                throw ContainerCLIError.apiServerRunning
            } catch {
                logger.error("Failed to stop container \(id): \(error)")
                failed.append((id, error))
            }
        }

        if !failed.isEmpty {
            let failures = failed.map({ "\($0.0): \($0.1)" }).joined(separator: "\n")
            let message = "Failed to stop one or more containers: \n\(failures)"

            throw ContainerizationError(.internalError, message: message)
        }
    }

    /// Stops containers, giving each one's process time to exit before forcing it.
    ///
    /// - Parameters:
    ///   - snapshots: The containers to stop.
    ///   - timeoutSeconds: How long to wait for each process to exit after sending it `SIGTERM`.
    /// - Throws: An error that lists each container that couldn't be stopped.
    public func stop(snapshots: [ContainerSnapshot], timeoutSeconds: Int32) async throws {
        try await stop(ids: snapshots.map(\.configuration.id), timeoutSeconds: timeoutSeconds)
    }

    /// Deletes containers, along with their data and any reports about them.
    ///
    /// - Parameters:
    ///   - ids: The IDs of the containers to delete.
    ///   - force: Whether to stop a running container and delete it, rather than leave it.
    /// - Throws: ``ContainerCLIError/apiServerRunning`` while the system is read-only, or an error that lists each container that couldn't be deleted.
    public func delete(ids: [String], force: Bool) async throws {
        let service = try containerSystem.containerService
        let snapshots = await service.list()

        var deleted: [String] = []
        var failed: [(String, Error)] = []

        for id in ids {
            do {
                guard
                    let container = snapshots.first(where: {
                        $0.configuration.id == id
                    })
                else {
                    throw ContainerizationError(.notFound, message: "Container not found: \(id)")
                }

                if container.status == .running && !force {
                    throw ContainerizationError(.invalidState, message: "container: \(id) is running")
                }

                if container.status == .running && force {
                    try await service.stop(id: id, options: .default)
                }

                try await service.delete(id: id)

                deleted.append(id)
            } catch ContainerCLIError.apiServerRunning {
                // Refused for the whole system, so for every one of them.
                throw ContainerCLIError.apiServerRunning
            } catch {
                logger.error("Failed to delete container \(id): \(error)")
                failed.append((id, error))
            }
        }

        try await containerSystem.reportService.delete(named: deleted, ofKind: [.container])

        if !failed.isEmpty {
            let failures = failed.map({ "\($0.0): \($0.1)" }).joined(separator: "\n")
            let message = "Failed to delete one or more containers: \n\(failures)"

            throw ContainerizationError(.internalError, message: message)
        }
    }

    /// Deletes containers, along with their data and any reports about them.
    ///
    /// - Parameters:
    ///   - snapshots: The containers to delete.
    ///   - force: Whether to stop a running container and delete it, rather than leave it.
    /// - Throws: An error that lists each container that couldn't be deleted.
    public func delete(snapshots: [ContainerSnapshot], force: Bool) async throws {
        try await delete(ids: snapshots.map(\.configuration.id), force: force)
    }

    // MARK: - Private Helper Methods

    private func writeCIDFile(path: String, id: String) throws {
        let data = id.data(using: .utf8)
        var attributes = [FileAttributeKey: Any]()
        attributes[.posixPermissions] = 0o644

        let success = FileManager.default.createFile(atPath: path, contents: data, attributes: attributes)

        guard success else {
            logger.error("Failed to write the CID file at \(path)")

            throw ContainerizationError(
                .internalError,
                message: "failed to create cidfile at \(path): \(errno)"
            )
        }
    }

    /// Split a shell-like command string into components, respecting double and single quotes.
    private static func shellSplit(_ command: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inDouble = false
        var inSingle = false

        for ch in command {
            if ch == "\"" && !inSingle {
                inDouble.toggle()
            } else if ch == "'" && !inDouble {
                inSingle.toggle()
            } else if ch == " " && !inDouble && !inSingle {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    /// Returns the ID a new container will have: its name, or a generated ID if it has none.
    ///
    /// The ID is settled before the container is created, so work on the container can be tracked from
    /// the start.
    ///
    /// - Parameter name: The name to give the container, or `nil`.
    /// - Returns: The name, or a generated ID if `name` is `nil` or empty.
    /// - Throws: An error if the name isn't a valid container name.
    public static func createContainerID(name: String?) throws -> String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !trimmedName.isEmpty else {
            return UUID().uuidString.lowercased()
        }

        guard EntityName.isValid(trimmedName) else {
            let message = """
                Invalid container name '\(trimmedName)': must start with a letter or number and contain only 
                letters, numbers, underscores, periods, and hyphens.
                """
            throw ContainerizationError(.invalidArgument, message: message)
        }

        return trimmedName
    }

    private func resolveImage(
        reference: String,
        platform: Platform,
        insecure: Bool,
        imageService: any ImageService,
        progress: Progress
    ) async throws -> ImageDescription {
        let existingImages = try await imageService.list()

        // Try exact match first
        if let existing = existingImages.first(where: {
            $0.reference == reference
        }) {
            return existing
        }

        // Try matching by comparing digests - most reliable
        let matchingByDigest = existingImages.first { image in
            // If the input reference contains a digest, match by digest
            if reference.contains("@sha256:") {
                return image.digest
                    == reference.split(separator: "@").last.map(String.init)
            }
            return false
        }

        if let existing = matchingByDigest {
            return existing
        }

        // Try matching by parsing the reference to handle different formats
        // e.g., "alpine:latest" should match "docker.io/library/alpine:latest"
        if let parsedRef = try? ContainerizationOCI.Reference.parse(reference) {
            let matchingImage = existingImages.first { image in
                guard
                    let imageRef = try? ContainerizationOCI.Reference.parse(image.reference)
                else {
                    return false
                }

                // Extract just the repository name without registry
                let refNameComponents = parsedRef.name.split(separator: "/")
                let refShortName = refNameComponents.last ?? Substring(parsedRef.name)

                let imageNameComponents = imageRef.name.split(separator: "/")
                let imageShortName = imageNameComponents.last ?? Substring(imageRef.name)

                // Match on short name and tag
                let nameMatch = refShortName == imageShortName
                let tagMatch = (parsedRef.tag ?? "latest") == (imageRef.tag ?? "latest")

                return nameMatch && tagMatch
            }

            if let existing = matchingImage {
                return existing
            }
        }

        return try await imageService.pull(
            reference: reference,
            platform: platform,
            insecure: insecure,
            progressUpdate: progress.updateHandler()
        )
    }

    private func createContainerConfig(
        id: String,
        imageReference: String,
        arguments: [String],
        process: ContainerProcess,
        configuration: ContainerConfiguration,
        options: ContainerManagementOptions,
        registryScheme: String,
        progress: Progress
    ) async throws -> (ContainerConfiguration, Kernel) {
        // What was asked for, which the sheet filled in; what follows settles
        // only what could not be known until now.
        var config = configuration
        let platform = config.platform

        let scheme = try RequestScheme(registryScheme)
        let insecure = scheme == .http

        // Normalize image reference to handle short names like "alpine:latest"
        let processedReference = try Reference.normalized(imageReference)
            .description

        let imageService = try containerSystem.imageService

        progress.totalUnitCount = 5

        // Resolve image - check local first, then pull if needed
        try Task.checkCancellation()
        let imageDescription = try await progress.performStep("Fetching image") { step in
            try await resolveImage(
                reference: processedReference,
                platform: platform,
                insecure: insecure,
                imageService: imageService,
                progress: step
            )
        }

        try Task.checkCancellation()
        try await progress.performStep("Unpacking image") { step in
            try await imageService.unpack(
                description: imageDescription,
                platform: platform,
                progressUpdate: step.updateHandler()
            )
        }

        try Task.checkCancellation()
        let kernel = try await progress.performStep("Fetching kernel") { _ in
            try await getKernel(options: options)
        }

        let initImageReference: String = DefaultsStore.get(key: .defaultInitImage)

        try Task.checkCancellation()
        let initImageDescription = try await progress.performStep("Fetching init image") { step in
            try await imageService.pull(
                reference: initImageReference,
                platform: .current,
                insecure: insecure,
                progressUpdate: step.updateHandler()
            )
        }

        try Task.checkCancellation()
        try await progress.performStep("Unpacking init image") { step in
            try await imageService.unpack(
                description: initImageDescription,
                platform: platform,
                progressUpdate: step.updateHandler()
            )
        }

        let image = try await imageService.image(for: imageDescription.reference)
        let imageConfig = try await image.config(for: platform).config
        config.id = id
        config.image = imageDescription
        config.initProcess = try parseProcessConfiguration(
            arguments: arguments,
            process: process,
            options: options,
            config: imageConfig
        )
        config.creationDate = Date()
        config.stopSignal = config.stopSignal ?? imageConfig?.stopSignal
        config.networks = try getAttachmentConfigurations(containerId: id, networkIds: options.networks)

        // Without nameservers, the runtime points the container at its network's gateway.
        if options.dnsDisabled {
            config.dns = nil
        } else {
            config.dns = ContainerConfiguration.DNSConfiguration(
                nameservers: options.dnsNameservers,
                domain: options.dnsDomain ?? DefaultsStore.getOptional(key: .defaultDNSDomain),
                searchDomains: options.dnsSearchDomains,
                options: options.dnsOptions
            )
        }

        if Platform.current.architecture == "arm64"
            && platform.architecture == "amd64"
        {
            config.rosetta = true
        }

        return (config, kernel)
    }

    private func getAttachmentConfigurations(
        containerId: String,
        networkIds: [String]
    ) throws -> [AttachmentConfiguration] {
        // make an FQDN for the first interface
        let fqdn: String?
        if !containerId.contains(".") {
            // add default domain if it exists, and container ID is unqualified
            if let dnsDomain = DefaultsStore.getOptional(key: .defaultDNSDomain) {
                fqdn = "\(containerId).\(dnsDomain)."
            } else {
                fqdn = nil
            }
        } else {
            // use container ID directly if fully qualified
            fqdn = "\(containerId)."
        }

        guard networkIds.isEmpty else {
            // networks may only be specified for macOS 26+
            guard #available(macOS 26, *) else {
                logger.error("Networks were asked for on a macOS that cannot attach them")

                throw ContainerizationError(
                    .invalidArgument,
                    message: "non-default network configuration requires macOS 26 or newer"
                )
            }

            // attach the first network using the fqdn, and the rest using just the container ID
            return networkIds.enumerated().map { item in
                guard item.offset == 0 else {
                    return AttachmentConfiguration(
                        network: item.element,
                        options: AttachmentOptions(hostname: containerId, mtu: 1280)
                    )
                }
                return AttachmentConfiguration(
                    network: item.element,
                    options: AttachmentOptions(hostname: fqdn ?? containerId, mtu: 1280)
                )
            }
        }

        let defaultNetworkName = "default"

        // if no networks specified, attach to the default network
        return [
            AttachmentConfiguration(
                network: defaultNetworkName,
                options: AttachmentOptions(hostname: fqdn ?? containerId, mtu: 1280)
            )
        ]
    }

    private func getKernel(options: ContainerManagementOptions) async throws -> Kernel {
        let kernelService = try containerSystem.kernelService

        // For the image itself we'll take the user input and try with it as we can do userspace
        // emulation for x86, but for the kernel we need it to match the hosts architecture.
        let s: SystemPlatform = .current
        if let userKernel = options.kernel {
            guard FileManager.default.fileExists(atPath: userKernel) else {
                logger.error("Kernel not found at \(userKernel)")

                throw ContainerizationError(.notFound, message: "Kernel file not found at path \(userKernel)")
            }
            let p = URL(filePath: userKernel)
            return .init(path: p, platform: s)
        }

        return try await kernelService.getDefaultKernel(platform: s)
    }

    private func parseProcessConfiguration(
        arguments: [String],
        process: ContainerProcess,
        options: ContainerManagementOptions,
        config: ContainerizationOCI.ImageConfig?
    ) throws -> ProcessConfiguration {

        let imageEnvVars = config?.env ?? []
        let envvars = try Parser.allEnv(
            imageEnvs: imageEnvVars,
            envFiles: process.envFile,
            envs: process.environments
        )

        let workingDir: String = {
            if let cwd = process.workingDirectory {
                return cwd
            }
            if let cwd = config?.workingDir {
                return cwd
            }
            return "/"
        }()

        let processArguments: [String]? = {
            var result: [String] = []
            var hasEntrypointOverride: Bool = false

            // ensure the entrypoint is honored if it has been explicitly set by the user
            if let entrypoint = options.entryPoint, !entrypoint.isEmpty {
                // Split the entrypoint string into executable + arguments,
                // respecting quoted substrings (e.g. sh -c "echo hello" → ["sh", "-c", "echo hello"])
                result = Self.shellSplit(entrypoint)
                hasEntrypointOverride = true
            } else if let entrypoint = config?.entrypoint, !entrypoint.isEmpty {
                result = entrypoint
            }

            if !arguments.isEmpty {
                result.append(contentsOf: arguments)
            } else {
                if let cmd = config?.cmd, !hasEntrypointOverride, !cmd.isEmpty {
                    result.append(contentsOf: cmd)
                }
            }

            return result.count > 0 ? result : nil
        }()

        guard let commandToRun = processArguments, let command = commandToRun.first else {
            logger.error("Nothing to run: no command from the image or the container")
            let message = "Command/Entrypoint not specified for container process"

            throw ContainerizationError(.invalidArgument, message: message)
        }

        let defaultUser: ProcessConfiguration.User = {
            if let u = config?.user {
                return .raw(userString: u)
            }
            return .id(uid: 0, gid: 0)
        }()

        let (user, additionalGroups) = Parser.user(
            user: process.user,
            uid: process.uid,
            gid: process.gid,
            defaultUser: defaultUser
        )

        return .init(
            executable: command,
            arguments: [String](commandToRun.dropFirst()),
            environment: envvars,
            workingDirectory: workingDir,
            terminal: process.tty,
            user: user,
            supplementalGroups: additionalGroups
        )
    }
}
