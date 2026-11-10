//
//  ContainerSystem.swift
//  Containers
//
//  The container system: its mode, status and lifecycle, and the services it runs.
//
//  Created by Axel Martinez on 2026/02/08.
//

import Containerization
import ContainerizationError
import ContainerizationOCI
import Foundation
import Logging
import Observation

/// The container system the app runs in process: it starts and stops the services that run containers,
/// and reports its status.
///
/// Start the container system before you use the managers. The first start installs what the system
/// needs, such as the Linux kernel, and reports it through ``setupProgress``.
///
/// The services are created when the system starts and released when it stops. Managers reach them
/// through the `…Service` properties, which throw while the system is stopped. While the system is
/// read-only, they're the read-only variants, which refuse what would write the folder.
@Observable
@MainActor
public class ContainerSystem {
    /// The container system the app and every manager use.
    public static let shared = ContainerSystem()

    /// Apple's container CLI, whose folder the system works in with ``Mode/cliCompatibility``.
    public let cli: ContainerCLI

    let logger: Logger

    private static let bootstrapLogging: Void = LoggingSystem.bootstrap { label in
        let category = label.split(separator: ".").last.map(String.init) ?? label
        return OSLogHandler(subsystem: "app.containers", category: category)
    }

    private init() {
        _ = Self.bootstrapLogging
        var logger = Logger(label: "app.containers.system")
        #if DEBUG
        logger.logLevel = .debug
        #else
        logger.logLevel = .info
        #endif
        self.logger = logger
        self.cli = ContainerCLI()
    }

    #if DEBUG
    /// Creates a container system for tests, which subclass it to provide services of their own.
    init(
        cliStatus: @escaping @Sendable () async throws -> ContainerCLI.Status = {
            ContainerCLI.Status(isInstalled: true, isRunning: false, cliVersion: "1.6.1")
        }
    ) {
        _ = Self.bootstrapLogging
        var logger = Logger(label: "app.containers.system.test")
        logger.logLevel = .debug
        self.logger = logger
        self.cli = ContainerCLI(status: cliStatus)
    }
    #endif

    // MARK: - Mode

    /// Whose container system the app works with.
    public enum Mode: String, Sendable {
        /// The app's own: it installs the Linux kernel and the init image the first time it starts,
        /// and runs containers itself.
        case `default`
        /// Apple's container CLI's: the app works in the CLI's folder, managing it while the CLI's
        /// API server is stopped and only reading it while the API server runs.
        case cliCompatibility
    }

    /// How the container system gets what it needs to run containers, from the next start on.
    public var mode: Mode = .default

    /// The resolver folder the user gave the app access to, read for the localhost domains `container system dns create`
    /// makes; it takes effect the next time the system starts.
    public var resolverDirectory: URL?

    // MARK: - Status

    /// The stages of the container system's life cycle.
    public enum Status: Equatable {
        /// The container system isn't running.
        case notStarted
        /// The container system is starting, and may be installing what it needs first.
        case starting
        /// The container system is running, and containers can be created and run.
        case running
        /// The container system is stopping its containers and services.
        case stopping
        /// The container system is running beside the container CLI's API server, in ``Mode/cliCompatibility``, and only
        /// reads its folder: images, containers and volumes can be looked at and images saved.
        case readOnly
        /// The last start failed. ``ContainerSystem/startupError`` describes why.
        case failed
    }

    /// The stage the container system is in.
    public internal(set) var status: Status = .notStarted

    /// Ends a start or a stop: failed if ``startupError`` says so, and not started otherwise, as after a
    /// start that stopped to ask about the kernel.
    func settleStopped() {
        if let startupError, !(startupError is SetupError) {
            status = .failed
        } else {
            status = .notStarted
        }
    }

    /// Whether the container system is running, by itself or alongside the CLI, so the managers can be used.
    public var isRunning: Bool {
        status == .running || status == .readOnly
    }

    /// Whether the container system only reads its folder, because it runs beside the container CLI's
    /// API server, which leaves it only the work that doesn't collide with the CLI's.
    public var isReadOnly: Bool { status == .readOnly }

    /// The error that made the last start fail, or `nil` if it didn't fail.
    public internal(set) var startupError: (any Error)?

    /// The progress of installing what the container system needs, such as the Linux kernel and the
    /// init image, while a start installs it.
    ///
    /// This property is `nil` when nothing is being installed.
    public internal(set) var setupProgress: Progress?

    // MARK: - Kernel

    public enum SetupError: LocalizedError, Equatable {
        case kernelInstallNotConfirmed

        public var errorDescription: String? {
            "No default kernel is configured. Install the recommended default kernel to continue."
        }
    }

    public var needsKernelConfirmation: Bool {
        startupError as? SetupError == .kernelInstallNotConfirmed
    }

    public nonisolated static var defaultKernelURL: URL? {
        URL(string: DefaultsStore.get(key: .defaultKernelURL))
    }

    // MARK: - State the Managers Observe

    var lastContainerStateChange = Date()
    /// When the CLI last changed the images, while the system is read-only.
    var lastSharedImageChange = Date()
    /// When the CLI last made or removed a volume, while the system is read-only.
    var lastSharedVolumeChange = Date()

    // MARK: - Reports

    var reports: [Report] = []

    // MARK: - Lifecycle

    var isSwitchingToReadOnly = false
    /// Watches the CLI's folder for its changes, from the system's start until it's stopped.
    let folderWatcher = ContainerCLI.FolderWatcher()
    private var startTask: Task<Void, Error>?

    /// Starts the container system in ``mode``, installing what it needs the first time unless it
    /// starts read-only.
    ///
    /// - Parameters:
    ///   - appRoot: The folder where the container system keeps its data.
    ///   - installingKernel: Whether the user agreed to download the default kernel if it's missing.
    /// - Throws: An error if the system can't install what it needs, or start its storage or services.
    public func start(appRoot: URL, installingKernel: Bool = false) async throws {
        switch status {
        case .starting, .running, .readOnly: return
        case .notStarted, .stopping, .failed: break
        }

        logger.info("Starting system", metadata: ["appRoot": "\(appRoot.path)", "mode": "\(mode.rawValue)"])

        startupError = nil
        status = .starting

        let task = Task { [self, mode] in
            // A start that fails before its services do, such as on the CLI's checks, ends here too.
            defer {
                if status == .starting {
                    settleStopped()
                }
            }

            var startsReadOnly = false

            switch mode {
            case .cliCompatibility:
                let status = try await requireCLICompatibility(over: appRoot)
                let apiServerUsesFolder = status.isRunning && (status.appRoot.map { $0.isSameFolder(as: appRoot) } ?? true)

                DefaultsStore.configuration = await configuration(in: appRoot)

                // The system manages the CLI's folder while its API server is stopped, and only reads it while the API server runs.
                startsReadOnly = isSwitchingToReadOnly || apiServerUsesFolder

                isSwitchingToReadOnly = false

                if !startsReadOnly {
                    watchFolder(appRoot, onAPIServerStart: .switchToReadOnly)
                }
            case .default:
                try requireOwnFolder(appRoot)

                DefaultsStore.configuration = await configuration(in: appRoot)
                // A CLI started on the folder later, with `--app-root`, makes it the CLI's.
                watchFolder(appRoot, onAPIServerStart: .stop)
            }

            do {
                try await launch(appRoot: appRoot, readOnly: startsReadOnly, installingKernel: installingKernel)
            } catch {
                // Left stopped to ask about the kernel, the system still follows the CLI starting.
                if !(mode == .cliCompatibility && error is SetupError) {
                    folderWatcher.stop()
                }

                throw error
            }
        }

        startTask = task

        defer {
            if startTask == task {
                startTask = nil
            }
        }

        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }

        if isReadOnly {
            watchFolder(appRoot, onAPIServerStart: .ignore)
        }
    }

    /// Cancels a start that's in progress, including one another caller began.
    public func cancelStart() {
        logger.info("Cancelling start")
        startTask?.cancel()
    }

    /// Stops the container system, and every container that's running.
    public func stop() async throws {
        logger.info("Stopping system")

        let appRoot = self.appRoot

        folderWatcher.stop()

        try await shutdown()

        // Stopped with compatibility on, the system still shows the CLI's folder once the CLI starts.
        if mode == .cliCompatibility, let appRoot {
            watchFolder(appRoot, onAPIServerStart: .switchToReadOnly)
        }
    }

    /// Returns the disk space the container system's data uses, in bytes, or `nil` if it isn't running.
    public func diskUsage() async -> Int64? {
        guard let appRoot else { return nil }
        return await FileIO.shared.allocatedSize(of: appRoot)
    }

    // MARK: - Services

    private var dnsService: DNSService?
    private var isAccessingAppRootSecurityScope = false
    /// The folder the running system keeps its data in, or `nil` while it's stopped.
    var appRoot: URL?

    /// The services the system made when it started, or `nil` while it's stopped.
    private var services: Services?

    /// The error for work that needs the system running while it's stopped.
    nonisolated static var notRunningError: ContainerizationError {
        ContainerizationError(.internalError, message: "Container system not running")
    }

    /// The value from the system's services, which throws while the system is stopped.
    private func service<Value>(_ value: KeyPath<Services, Value>) throws -> Value {
        guard let services else {
            throw Self.notRunningError
        }

        return services[keyPath: value]
    }

    var containerService: any ContainerService {
        get throws { try service(\.containerService) }
    }

    var imageService: any ImageService {
        get throws { try service(\.imageService) }
    }

    var networkService: any NetworkService {
        get throws { try service(\.networkService) }
    }

    var volumeService: any VolumeService {
        get throws { try service(\.volumeService) }
    }

    var kernelService: KernelService {
        get throws { try service(\.kernelService) }
    }

    var reportService: ReportService {
        get throws {
            guard let reportService = try service(\.reportService) else {
                throw ContainerizationError(.unsupported, message: "Reports aren't kept while the system is read-only")
            }

            return reportService
        }
    }

    /// Launches what the system runs: makes its services, installs the kernel and the init image the
    /// first time unless it's read-only, and starts the DNS servers. ``start(appRoot:installingKernel:)``
    /// calls it once the CLI's checks pass; tests override it to run without virtual machines.
    ///
    /// - Parameters:
    ///   - appRoot: The folder where the container system keeps its data.
    ///   - readOnly: Whether the system only reads the folder, beside the container CLI's API server,
    ///     which leaves the kernel, the init image and everything that runs a virtual machine to the CLI.
    ///   - installingKernel: Whether the user agreed to download the default kernel if it's missing.
    /// - Throws: An error if the system can't install what it needs, or start its storage or services.
    func launch(appRoot: URL, readOnly: Bool, installingKernel: Bool) async throws {
        switch status {
        case .running, .readOnly, .stopping:
            logger.info("System already running or stopping")
            return
        case .notStarted, .failed, .starting:
            break
        }

        status = .starting

        logger.info("Starting services...", metadata: ["readOnly": "\(readOnly)"])

        startupError = nil
        isAccessingAppRootSecurityScope = appRoot.startAccessingSecurityScopedResource()

        do {
            try createDataDirectories(appRoot: appRoot)

            let services = try makeServices(appRoot: appRoot, readOnly: readOnly)

            self.services = services
            self.appRoot = appRoot
            reports = []
            await observe(services)

            logger.info("Services initialized successfully")

            // The kernel's default link and the init image are the CLI's to install, and nothing that
            // needs them runs here beside it.
            if !readOnly {
                try await installPrerequisites(installingKernel: installingKernel)
            }

            // Beside the CLI's running API server, its own servers answer for its containers.
            if !readOnly {
                let dnsService = DNSService(log: logger)
                await dnsService.start(containers: services.containerService, resolverDirectory: resolverDirectory)
                self.dnsService = dnsService
            }

            status = readOnly ? .readOnly : .running
            startupError = nil

            logger.info("Container system started successfully")

        } catch {
            let wasCancelled = error is CancellationError || Task.isCancelled

            startupError = wasCancelled ? nil : error
            settleStopped()

            if isAccessingAppRootSecurityScope {
                appRoot.stopAccessingSecurityScopedResource()
                isAccessingAppRootSecurityScope = false
            }

            discardServices()

            if wasCancelled {
                logger.info("Start cancelled; system left stopped")
            } else {
                logger.error("Failed to start system: \(error)")
            }

            throw error
        }
    }

    /// Shuts down what the system runs: stops every running container and the DNS servers, and lets go of
    /// the services. ``stop()`` calls it; tests override it to run without virtual machines.
    func shutdown() async throws {
        guard status == .running || status == .readOnly else {
            logger.info("System not running or already stopping")
            return
        }

        status = .stopping

        logger.info("Stopping container system...")

        let appRoot = self.appRoot

        await stopRunningContainers()
        discardServices()

        settleStopped()

        if isAccessingAppRootSecurityScope {
            appRoot?.stopAccessingSecurityScopedResource()
            isAccessingAppRootSecurityScope = false
        }

        logger.info("Container system stopped")
    }

    private func stopRunningContainers() async {
        if let service = services?.containerService {
            let list = await service.list()
            for container in list where container.status == .running {
                do {
                    try await service.stop(
                        id: container.configuration.id,
                        options: .default
                    )
                } catch {
                    logger.error(
                        "Error stopping container \(container.configuration.id): \(error)"
                    )
                }
            }
        }
    }

    /// Lets go of the services, so that the next start builds them again.
    private func discardServices() {
        if let dnsService {
            Task { await dnsService.stop() }
        }

        dnsService = nil
        services = nil
        appRoot = nil
    }

}
