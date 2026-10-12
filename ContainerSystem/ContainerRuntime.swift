//
//  ContainerRuntime.swift
//  Containers
//
//  Manages the container system lifecycle and services
//
//  Created by Axel Martinez on 2026/02/04.
//

import Containerization
import ContainerizationError
import ContainerizationOCI
import Foundation
import Logging

/// Container runtime lifecycle and services.
/// Owns all services and provides factory methods for creating managers.
@Observable
@MainActor
class ContainerRuntime {
    /// Shared runtime instance - internal to ContainerSystem module
    static let shared = ContainerRuntime()

    /// Private initializer - forces use of singleton in production
    private init() {
        _ = Self._bootstrapLogging
        var l = Logger(label: "app.containers.system")
        #if DEBUG
        l.logLevel = .debug
        #else
        l.logLevel = .info
        #endif
        self.logger = l
    }

    #if DEBUG
    /// Internal initializer for testing - allows subclassing
    init(forTesting: Bool) {
        _ = Self._bootstrapLogging
        var l = Logger(label: "app.containers.system.test")
        l.logLevel = .debug
        self.logger = l
    }
    #endif

    // MARK: - Nested Types

    struct PluginProcessInfo {
        let process: Foundation.Process
        let plugin: Plugin
        let instanceId: String
        let standardOutput: Pipe?
        let standardError: Pipe?
    }

    // MARK: - Observable State

    var isRunning: Bool = false
    var isStarting: Bool = false
    var isStopping: Bool = false
    var startupError: Error?
    var lastContainerStateChange: Date = Date()
    var reports: [Report] = []

    /// What a first start is fetching, while it fetches it.
    var setupProgress: Progress?

    @ObservationIgnored var reportStore: ReportStore?

    var pluginProcesses: [String: PluginProcessInfo] = [:]

    // Current configuration
    var appRoot: URL?
    var isAccessingAppRootSecurityScope = false

    // MARK: - Private State

    private var servicesInitialized = false
    private var pluginLoader: PluginLoader?
    private var containersService: ContainersService?
    private var imagesService: ImagesService?
    private var kernelService: KernelService?
    private var contentStore: ContentStore?

    let logger: Logger

    private static let _bootstrapLogging: Void = LoggingSystem.bootstrap { label in
        let category = label.split(separator: ".").last.map(String.init) ?? label
        return OSLogHandler(subsystem: "app.containers", category: category)
    }

    // MARK: - Service Accessors

    func getContainersService() async throws -> ContainersService {
        guard let service = containersService else {
            throw ContainerizationError(
                .internalError,
                message: "Containers service not initialized"
            )
        }
        return service
    }

    func getImagesService() async throws -> ImagesService {
        guard let service = imagesService else {
            throw ContainerizationError(
                .internalError,
                message: "Images service not initialized"
            )
        }

        return service
    }

    func getKernelService() async throws -> KernelService {
        guard let service = kernelService else {
            throw ContainerizationError(
                .internalError,
                message: "Kernel service not initialized"
            )
        }

        return service
    }

    func getAppRoot() throws -> URL {
        guard let appRoot = appRoot else {
            throw ContainerizationError(
                .internalError,
                message: "App root not initialized"
            )
        }

        return appRoot
    }

    func getContentStore() throws -> ContentStore {
        guard let contentStore = contentStore else {
            throw ContainerizationError(
                .internalError,
                message: "Content store not initialized"
            )
        }

        return contentStore
    }

    // MARK: - Internal API

    /// Start the container system and initialize all managers
    func start(appRoot: URL) async throws {
        guard !isRunning && !isStarting else {
            logger.info("System already running or starting")
            return
        }

        logger.info("Starting container system...")

        self.isStarting = true
        self.startupError = nil
        self.appRoot = appRoot
        self.isAccessingAppRootSecurityScope =
            appRoot.startAccessingSecurityScopedResource()

        defer {
            isStarting = false
        }

        do {
            try createDataDirectories(appRoot: appRoot)
            try await initializeServices(appRoot: appRoot)
            try await installPrerequisites()

            isRunning = true
            startupError = nil

            logger.info("Container system started successfully")

        } catch {
            self.isRunning = false

            let wasCancelled = error is CancellationError || Task.isCancelled

            self.startupError = wasCancelled ? nil : error

            if isAccessingAppRootSecurityScope {
                appRoot.stopAccessingSecurityScopedResource()
                isAccessingAppRootSecurityScope = false
            }

            self.appRoot = nil

            // Cleanup on failure.
            stopAllPlugins()
            discardServices()

            if wasCancelled {
                logger.info("Start cancelled; system left stopped")
            } else {
                logger.error("Failed to start system: \(error)")
            }

            throw error
        }
    }

    /// Stop the container system and all managers
    func stop() async throws {
        guard isRunning && !isStopping else {
            logger.info("System not running or already stopping")
            return
        }

        isStopping = true

        defer { isStopping = false }

        logger.info("Stopping container system...")

        stopAllPlugins()

        await shutdownServices()

        isRunning = false

        if isAccessingAppRootSecurityScope {
            appRoot?.stopAccessingSecurityScopedResource()
            isAccessingAppRootSecurityScope = false
        }
        appRoot = nil

        logger.info("Container system stopped")
    }

    // MARK: - Private Helpers

    /// Initialize all services for sandboxed mode
    private func initializeServices(appRoot: URL) async throws {
        guard !servicesInitialized else {
            logger.info("Services already initialized")
            return
        }

        logger.info("Initializing services...")

        // Initialize images service (must come before containers service)
        let imagesRoot = appRoot.appendingPathComponent("images")

        try FileManager.default.createDirectory(
            at: imagesRoot,
            withIntermediateDirectories: true
        )

        let contentStore = try LocalContentStore(
            path: imagesRoot.appendingPathComponent("content")
        )
        let imageStore = try ImageStore(
            path: imagesRoot,
            contentStore: contentStore
        )
        let snapshotsPath = imagesRoot.appendingPathComponent("snapshots")
        let imagesService = try ImagesService(
            contentStore: contentStore,
            imageStore: imageStore,
            snapshotsPath: snapshotsPath,
            log: logger
        )

        self.imagesService = imagesService
        self.contentStore = contentStore

        let service = try ContainersService(
            appRoot: appRoot,
            imagesService: imagesService,
            log: logger
        )

        self.containersService = service

        let kernel = try KernelService(log: logger, appRoot: appRoot)

        self.kernelService = kernel

        servicesInitialized = true

        logger.info("Services initialized successfully")

        // Register callback to update runtime state when containers change
        await service.addStateChangeCallback { @MainActor [weak self] in
            guard let self = self else { return }

            self.lastContainerStateChange = Date()
        }
    }

    /// Shutdown all services
    private func shutdownServices() async {
        // Stop all running containers
        if let service = containersService {
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

        discardServices()
    }

    /// Lets go of the services, so that the next start builds them again
    /// rather than reaching for ones whose plugins have been stopped.
    private func discardServices() {
        containersService = nil
        imagesService = nil
        kernelService = nil
        contentStore = nil
        pluginLoader = nil
        servicesInitialized = false
    }

    private func createDataDirectories(appRoot: URL) throws {
        logger.info("Creating data directories...")

        // Create app data directory with subdirectories
        try FileManager.default.createDirectory(
            at: appRoot,
            withIntermediateDirectories: true
        )

        // Create content directory (for image storage)
        try FileManager.default.createDirectory(
            at: appRoot.appendingPathComponent("content"),
            withIntermediateDirectories: true
        )
    }
}
