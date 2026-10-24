//
//  ContainersService.swift
//  Containers
//
//  A containers service that runs LinuxContainer.
//
//  Created by Axel Martinez on 2026/02/04.
//

import Containerization
import ContainerizationError
import ContainerizationExtras
import ContainerizationOCI
import Foundation
import Logging

/// A sandbox-compatible containers service that runs LinuxContainer in-process.
actor ContainersService {
    struct ContainerState {
        var snapshot: ContainerSnapshot
        var container: LinuxContainer?
        var bundle: Bundle?
        var exitMonitorTask: Task<Int32, Never>?
        var lastExitCode: Int32?
    }

    let log: Logger
    let appRoot: URL
    let containerRoot: URL
    let imagesService: ImagesService
    var containers: [String: ContainerState] = [:]
    var ipAllocations: [String: UInt8] = [:]
    var portForwarders: [String: PortForwarder] = [:]
    /// One lock per container, so booting or stopping one never waits on another.
    /// They're kept after a container is deleted: dropping a lock while a call
    /// waits on it would let a new one be made for the same ID.
    var containerLocks: [String: AsyncLock] = [:]

    /// Callbacks to invoke when container state changes
    var stateChangeCallbacks: [@Sendable @MainActor () -> Void] = []

    /// Register a callback to be invoked when container state changes
    func addStateChangeCallback(_ callback: @escaping @Sendable @MainActor () -> Void) {
        stateChangeCallbacks.append(callback)
    }

    init(appRoot: URL, imagesService: ImagesService, log: Logger) throws {
        let containerRoot = appRoot.appendingPathComponent("containers")

        try FileManager.default.createDirectory(at: containerRoot, withIntermediateDirectories: true)

        self.appRoot = appRoot
        self.containerRoot = containerRoot
        self.imagesService = imagesService
        self.log = log
        self.containers = Self.loadAtBoot(root: containerRoot, log: log)

        let count = containers.count

        log.info("ContainersService initialized with \(count) existing container(s)")
    }

    private static func loadAtBoot(root: URL, log: Logger) -> [String: ContainerState] {
        var results = [String: ContainerState]()

        guard
            let directories = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
        else {
            return results
        }

        for dir in directories where dir.isDirectory {
            do {
                let bundle = Bundle(path: dir)
                let config = try bundle.configuration

                if (try? bundle.createOptions)?.autoRemove ?? false {
                    log.info("Reaping auto-remove container \(config.id)")
                    try? bundle.delete()
                    continue
                }

                results[config.id] = ContainerState(
                    snapshot: ContainerSnapshot(
                        configuration: config,
                        status: .stopped,
                        networks: [],
                        startedDate: bundle.state.startedDate
                    ),
                    container: LinuxContainer?.none,
                    bundle: bundle
                )
                // Container restored from disk
            } catch {
                log.warning("Failed to load container bundle at \(dir.path): \(error)")
            }
        }
        return results
    }

    // MARK: - Internal API

    /// List containers with optional filters.
    func list(
        status: ContainerStatus? = nil,
        labelFilter: [String: String]? = nil,
        namePattern: String? = nil
    ) async -> [ContainerSnapshot] {
        var results = containers.values.map { $0.snapshot }

        if let status {
            results = results.filter { $0.status == status }
        }

        if let labelFilter {
            results = results.filter { snapshot in
                labelFilter.allSatisfy { key, value in
                    snapshot.configuration.labels[key] == value
                }
            }
        }

        if let namePattern, !namePattern.isEmpty {
            results = results.filter { snapshot in
                snapshot.id.localizedCaseInsensitiveContains(namePattern)
            }
        }

        return results.sorted { $0.configuration.id < $1.configuration.id }
    }

    func create(
        configuration: ContainerConfiguration,
        kernel: Kernel,
        options: ContainerCreateOptions
    ) async throws {
        // Creating container

        guard containers[configuration.id] == nil else {
            throw ContainerizationError(.exists, message: "container already exists: \(configuration.id)")
        }

        let path = bundlePath(for: configuration.id)
        let systemPlatform = kernel.platform

        // Get init filesystem
        let initFs = try await getInitBlock(for: systemPlatform.ociPlatform())

        // Create container bundle
        let bundle = try Bundle.create(
            path: path,
            initialFilesystem: initFs,
            kernel: kernel,
            containerConfiguration: configuration,
            options: options
        )

        do {
            // Get container image filesystem via in-process ImagesService (no XPC)
            let imageFs = try await imagesService.getImageSnapshot(
                description: configuration.image,
                platform: configuration.platform
            )
            try bundle.cloneContainerRootFs(cloning: imageFs, readonly: configuration.readOnly)

            let snapshot = ContainerSnapshot(configuration: configuration, status: .stopped, networks: [])

            containers[configuration.id] = ContainerState(
                snapshot: snapshot,
                container: LinuxContainer?.none,
                bundle: bundle
            )

            // Container created successfully
        } catch {
            log.error("Failed to create container: \(error)")
            try? bundle.delete()
            throw error
        }
    }

    // MARK: - Container State

    func containerState(for id: String) throws -> ContainerState {
        guard let state = containers[id] else {
            throw ContainerizationError(.notFound, message: "container with ID \(id) not found")
        }

        return state
    }

    /// The container's virtual machine, which only a booted container has.
    func runningContainer(id: String) throws -> LinuxContainer {
        guard let container = containers[id]?.container else {
            throw ContainerizationError(.invalidState, message: "container not running: \(id)")
        }

        return container
    }

    func bundlePath(for id: String) -> URL {
        containerRoot.appendingPathComponent(id)
    }

    /// The lock that keeps a container's boot and stop from overlapping, which
    /// would let both copy its state, wait, and write back over each other.
    func lock(for id: String) -> AsyncLock {
        if let lock = containerLocks[id] {
            return lock
        }

        let lock = AsyncLock()
        containerLocks[id] = lock
        return lock
    }

    /// Takes the container off disk and out of the list. The caller decides
    /// whether removing it is allowed and when observers hear about it.
    func removeContainer(id: String) {
        try? FileManager.default.removeItem(at: bundlePath(for: id))

        releaseIP(for: id)
        containers.removeValue(forKey: id)
    }

    /// Whether the container asked at create time to be taken away as soon as
    /// it stops, which is answered by the options kept in its bundle.
    func autoRemoves(_ state: ContainerState) -> Bool {
        guard let bundle = state.bundle else { return false }

        return (try? bundle.createOptions)?.autoRemove ?? false
    }

    private func getInitBlock(for platform: Platform) async throws -> Filesystem {
        let initImageRef: String = DefaultsStore.get(key: .defaultInitImage)
        let initDescription = try await imagesService.pull(
            reference: initImageRef,
            platform: platform,
            insecure: false,
            progressUpdate: nil
        )

        try await imagesService.unpack(
            description: initDescription,
            platform: platform,
            progressUpdate: nil
        )

        var fs = try await imagesService.getImageSnapshot(
            description: initDescription,
            platform: platform
        )

        fs.options = ["ro"]
        return fs
    }

    /// Notify all registered callbacks that container state changed
    func notifyStateChange() {
        for callback in stateChangeCallbacks {
            Task { @MainActor in
                callback()
            }
        }
    }
}
