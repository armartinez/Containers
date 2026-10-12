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
import ContainerizationOS
import Foundation
import Logging
import SystemPackage

private struct MultiWriter: Writer {
    let handles: [FileHandle]

    func close() throws {
        for handle in handles {
            try handle.close()
        }
    }

    func write(_ data: Data) throws {
        for handle in handles {
            try handle.write(contentsOf: data)
        }
    }
}

/// Answers a wait once, with whichever comes first: the container's exit, or the caller giving up on it.
private final class ExitWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Int32, Error>?
    private var answered = false

    func wait(for monitor: Task<Int32, Never>) async throws -> Int32 {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()

                // Cancelled before the wait even began.
                guard !answered else {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }

                self.continuation = continuation

                lock.unlock()

                Task {
                    let exitCode = await monitor.value
                    self.answer(with: .success(exitCode))
                }
            }
        } onCancel: {
            answer(with: .failure(CancellationError()))
        }
    }

    private func answer(with result: Result<Int32, Error>) {
        lock.lock()

        guard !answered else {
            lock.unlock()
            return
        }

        answered = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        continuation?.resume(with: result)
    }
}

private struct FileHandleReader: ReaderStream {
    let handle: FileHandle

    func stream() -> AsyncStream<Data> {
        .init { cont in
            self.handle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    cont.finish()
                    return
                }
                cont.yield(data)
            }
        }
    }
}

extension Filesystem {
    fileprivate var asMount: Containerization.Mount {
        switch self.type {
        case .tmpfs:
            return .any(
                type: "tmpfs",
                source: self.source,
                destination: self.destination,
                options: self.options
            )
        case .virtiofs:
            return .share(
                source: self.source,
                destination: self.destination,
                options: self.options
            )
        case .block(let format, _, _):
            return .block(
                format: format,
                source: self.source,
                destination: self.destination,
                options: self.options
            )
        case .volume(_, let format, _, _):
            return .block(
                format: format,
                source: self.source,
                destination: self.destination,
                options: self.options
            )
        }
    }

    fileprivate func isSocket() throws -> Bool {
        if !self.isVirtiofs {
            return false
        }
        let info = try File.info(self.source)

        return info.isSocket
    }
}

/// A sandbox-compatible containers service that runs LinuxContainer in-process.
actor ContainersService {
    private struct ContainerState {
        var snapshot: ContainerSnapshot
        var container: LinuxContainer?
        var bundle: Bundle?
        var exitMonitorTask: Task<Int32, Never>?
        var lastExitCode: Int32?
    }

    private let log: Logger
    private let appRoot: URL
    private let containerRoot: URL
    private let imagesService: ImagesService
    private var containers: [String: ContainerState] = [:]
    private var ipAllocations: [String: UInt8] = [:]
    private var portForwarders: [String: PortForwarder] = [:]
    private let containerLock = AsyncLock()

    /// Callbacks to invoke when container state changes
    private var stateChangeCallbacks: [@Sendable @MainActor () -> Void] = []

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

    func list() async -> [ContainerSnapshot] {
        containers.values.map { $0.snapshot }.sorted {
            $0.configuration.id < $1.configuration.id
        }
    }

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

        let path = containerRoot.appendingPathComponent(configuration.id)
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

    func bootstrap(id: String, stdio: [FileHandle?]) async throws {
        try await containerLock.withLock { _ in
            try await self._bootstrap(id: id, stdio: stdio)
        }
    }

    private func _bootstrap(id: String, stdio: [FileHandle?]) async throws {
        guard var state = containers[id] else {
            throw ContainerizationError(.notFound, message: "container with ID \(id) not found")
        }

        // Already bootstrapped
        if state.container != nil {
            return
        }

        let previousStatus = state.snapshot.status
        var hasBooted = false

        // Shown while the virtual machine boots, which is most of a start.
        state.snapshot.status = .starting
        containers[id] = state
        notifyStateChange()

        defer {
            if !hasBooted {
                containers[id]?.snapshot.status = previousStatus
                notifyStateChange()
            }
        }

        let bundle: ContainerSystem.Bundle

        if let existingBundle = state.bundle {
            bundle = existingBundle
        } else {
            let path = containerRoot.appendingPathComponent(id)
            bundle = Bundle(path: path)
        }

        let config = try bundle.configuration
        let bundleKernel = try bundle.kernel
        let initMount = await MainActor.run {
            bundle.initialFilesystem.asMount
        }
        let vmm = VZVirtualMachineManager(
            kernel: bundleKernel,
            initialFilesystem: initMount,
            rosetta: config.rosetta,
            logger: self.log
        )

        // Create the log file for container stdio
        let containerLogURL = bundle.path.appendingPathComponent("stdio.log")

        do {
            let fd = Darwin.open(containerLogURL.path, O_CREAT | O_RDONLY | O_TRUNC, 0o644)
            guard fd >= 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            Darwin.close(fd)
        }

        // Set up stdio writers
        let containerLog = try FileHandle(forWritingTo: containerLogURL)
        let stdout: MultiWriter = {
            if let h = stdio[1] {
                return MultiWriter(handles: [h, containerLog])
            }
            return MultiWriter(handles: [containerLog])
        }()

        let stderr: MultiWriter? = {
            if !config.initProcess.terminal {
                if let h = stdio[2] {
                    return MultiWriter(handles: [h, containerLog])
                }
                return MultiWriter(handles: [containerLog])
            }
            return nil
        }()

        let stdin: FileHandleReader? = {
            if let handle = stdio[0] {
                return FileHandleReader(handle: handle)
            }
            return nil
        }()

        let rootfs = try await MainActor.run {
            try bundle.containerRootfs.asMount
        }

        // Precompute mounts and sockets
        var precomputedMounts: [Containerization.Mount] = []
        var precomputedSockets: [UnixSocketConfiguration] = []

        for mount in config.mounts {
            if try await MainActor.run(body: { try mount.isSocket() }) {
                let socket = UnixSocketConfiguration(
                    source: URL(filePath: mount.source),
                    destination: URL(filePath: mount.destination)
                )
                precomputedSockets.append(socket)
            } else {
                let mnt = await MainActor.run { mount.asMount }
                precomputedMounts.append(mnt)
            }
        }

        // Allocate IP before the closure (actor-isolated state)
        let (ip, gw) = try allocateIP(for: id)

        let container = try LinuxContainer(id, rootfs: rootfs, vmm: vmm, logger: self.log) { czConfig in
            try Self.configureContainer(
                czConfig: &czConfig,
                config: config,
                precomputedMounts: precomputedMounts,
                precomputedSockets: precomputedSockets
            )

            // Configure NATInterface (IsolatedInterfaceStrategy pattern)
            czConfig.interfaces = [try NATInterface(ipv4Address: CIDRv4(ip), ipv4Gateway: IPv4Address(gw))]

            // Do not set hosts configuration - causes I/O errors when framework tries to write /etc/hosts
            // The framework will handle hosts automatically

            czConfig.process.stdout = stdout
            czConfig.process.stderr = stderr
            czConfig.process.stdin = stdin

            // The console is the only account of a boot that never reaches the
            // container process, which is when stdio stays empty.
            czConfig.bootLog = .file(path: bundle.bootLog, append: true)
        }

        do {
            try await container.create()

            state.container = container
            state.bundle = bundle
            state.snapshot.networks = [
                Attachment(
                    network: "nat",
                    hostname: id,
                    ipv4Address: try CIDRv4(ip),
                    ipv4Gateway: try IPv4Address(gw),
                    ipv6Address: CIDRv6?.none,
                    macAddress: MACAddress?.none
                )
            ]
            containers[id] = state
            hasBooted = true

            // Notify observers that networks have been assigned
            notifyStateChange()
        } catch {
            log.error("Failed to bootstrap container \(id): \(error)")
            releaseIP(for: id)
            throw error
        }
    }

    func startProcess(id: String, processID: String) async throws {
        // Starting process in container

        guard var state = containers[id] else {
            throw ContainerizationError(.notFound, message: "container with ID \(id) not found")
        }

        let isInit = id == processID
        if state.snapshot.status == .running && isInit {
            return
        }

        guard let container = state.container else {
            throw ContainerizationError(.invalidState, message: "container not bootstrapped: \(id)")
        }

        do {
            try await container.start()
        } catch {
            if isInit {
                // Booted, but it never got as far as running.
                containers[id]?.snapshot.status = .stopped
                notifyStateChange()
            }

            throw error
        }
        // Container init process started

        if isInit {
            let startedDate = Date()

            state.snapshot.status = .running
            state.snapshot.startedDate = startedDate

            // Kept on disk so the container still reports when it last ran
            // after the app has been quit and reopened.
            do {
                try state.bundle?.setState(Bundle.State(startedDate: startedDate))
            } catch {
                log.warning("Failed to record start date for container \(id): \(error)")
            }

            // Start port forwarding for published ports
            let config = state.snapshot.configuration
            if !config.publishedPorts.isEmpty {
                let forwarder = PortForwarder(log: self.log)
                for port in config.publishedPorts {
                    do {
                        try await forwarder.startForwarding(publishPort: port, container: container)
                    } catch {
                        log.warning("Failed to start port forwarding for \(port.hostPort) -> \(port.containerPort): \(error)")
                    }
                }
                portForwarders[id] = forwarder
            }

            // Monitor container exit in background
            let logger = self.log

            state.exitMonitorTask = Task { [weak self] in
                var exitCode: Int32 = 0
                do {
                    exitCode = try await container.wait().exitCode
                } catch {
                    logger.error("Error waiting for container \(id): \(error)")
                }
                await self?.handleContainerExit(id: id, exitCode: exitCode)
                return exitCode
            }

            containers[id] = state

            // Notify observers that container started
            notifyStateChange()
        }
    }

    /// Waits for the container's init process to exit and returns its code.
    func wait(id: String) async throws -> Int32 {
        guard let state = containers[id] else {
            throw ContainerizationError(.notFound, message: "container with ID \(id) not found")
        }

        // A container that exited before anyone waited on it has already torn
        // down its monitor, so the code it left behind is all there is.
        guard let monitor = state.exitMonitorTask else {
            return state.lastExitCode ?? 0
        }

        return try await ExitWaiter().wait(for: monitor)
    }

    /// What each running container is using right now. A container that
    /// cannot say, because it is on its way down, is left out.
    func resourceUsage() async -> [ContainerResourceUsage] {
        // Taken before the first await: the actor can change underneath it.
        let running = containers.compactMap { id, state in
            state.snapshot.status == .running
                ? state.container.map { (id, $0) } : nil
        }

        var usage: [ContainerResourceUsage] = []

        for (id, container) in running {
            guard
                let stats = try? await container.statistics(categories: [.memory, .cpu])
            else {
                continue
            }

            let entry = ContainerResourceUsage(
                id: id,
                memoryBytes: stats.memory?.usageBytes ?? 0,
                cpuUsageMicroseconds: stats.cpu?.usageUsec ?? 0
            )

            usage.append(entry)
        }

        return usage
    }

    func stop(id: String, options: ContainerStopOptions) async throws {
        try await containerLock.withLock { _ in
            try await self._stop(id: id, options: options)
        }
    }

    private func _stop(id: String, options: ContainerStopOptions) async throws {
        guard var state = containers[id] else {
            throw ContainerizationError(.notFound, message: "container with ID \(id) not found")
        }

        if let container = state.container {
            // Shown while the container winds down, which can last until the stop timeout.
            containers[id]?.snapshot.status = .stopping
            notifyStateChange()

            do {
                try await gracefulStopContainer(container, stopOpts: options)
            } catch let err as ContainerizationError {
                if err.code != .interrupted {
                    // It is still running, as far as anyone can tell.
                    containers[id]?.snapshot.status = state.snapshot.status
                    notifyStateChange()
                    throw err
                }
            } catch {
                log.error("Error during graceful stop of container \(id): \(error)")
            }
        }

        state.exitMonitorTask?.cancel()
        state.exitMonitorTask = nil
        state.snapshot.status = .stopped
        state.snapshot.networks = []
        state.container = nil
        releaseIP(for: id)

        // Stop port forwarding
        if let forwarder = portForwarders.removeValue(forKey: id) {
            await forwarder.stopAll()
        }

        containers[id] = state

        if autoRemoves(state) {
            removeContainer(id: id)
        }

        // Notify observers that container stopped
        notifyStateChange()
    }

    func delete(id: String) async throws {
        guard let state = containers[id] else {
            throw ContainerizationError(.notFound, message: "container with ID \(id) not found")
        }

        if state.snapshot.status == .running {
            throw ContainerizationError(.invalidState, message: "cannot delete running container")
        }

        removeContainer(id: id)
        notifyStateChange()
    }

    /// Takes the container off disk and out of the list. The caller decides
    /// whether removing it is allowed and when observers hear about it.
    private func removeContainer(id: String) {
        let path = containerRoot.appendingPathComponent(id)
        try? FileManager.default.removeItem(at: path)

        releaseIP(for: id)
        containers.removeValue(forKey: id)
    }

    /// Whether the container asked at create time to be taken away as soon as
    /// it stops, which is answered by the options kept in its bundle.
    private func autoRemoves(_ state: ContainerState) -> Bool {
        guard let bundle = state.bundle else { return false }

        return (try? bundle.createOptions)?.autoRemove ?? false
    }

    /// Execute a command in a running container and return its output (uses vsock, no networking needed).
    func exec(id: String, arguments: [String]) async throws -> String {
        guard let state = containers[id], let container = state.container else {
            throw ContainerizationError(.invalidState, message: "container not running: \(id)")
        }

        let outputURL = containerRoot.appendingPathComponent("\(id)-exec-output.tmp")

        FileManager.default.createFile(atPath: outputURL.path, contents: nil)

        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let writer = MultiWriter(handles: [outputHandle])

        let process = try await container.exec("exec-\(UUID().uuidString)") { config in
            config.arguments = arguments
            config.stdout = writer
            config.stderr = writer
        }

        try await process.start()

        let exitStatus = try await process.wait()

        try? writer.close()

        let output = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""

        try? FileManager.default.removeItem(at: outputURL)

        if exitStatus.exitCode != 0 {
            let message = "command failed with exit code \(exitStatus.exitCode): \(output)"
            throw ContainerizationError(.internalError, message: message)
        }

        return output
    }

    func dial(id: String, port: UInt32) async throws -> FileHandle {
        guard let state = containers[id], let container = state.container else {
            throw ContainerizationError(.invalidState, message: "container not running: \(id)")
        }

        // Dialing vsock port
        return try await container.dialVsock(port: port)
    }

    // MARK: - IP Allocation

    private func allocateIP(for id: String) throws -> (address: String, gateway: String) {
        if let existing = ipAllocations[id] {
            return (address: "192.168.64.\(existing)/24", gateway: "192.168.64.1")
        }
        for i: UInt8 in 2...254 {
            if !ipAllocations.values.contains(i) {
                ipAllocations[id] = i
                return (address: "192.168.64.\(i)/24", gateway: "192.168.64.1")
            }
        }
        throw ContainerizationError(.internalError, message: "no available IP addresses")
    }

    private func releaseIP(for id: String) {
        ipAllocations.removeValue(forKey: id)
    }

    // MARK: - Private Methods

    private func handleContainerExit(id: String, exitCode: Int32) {
        guard var state = containers[id] else {
            log.warning("Container \(id) not found during exit handling")
            return
        }
        state.lastExitCode = exitCode
        state.snapshot.status = .stopped
        state.snapshot.networks = []
        state.container = nil
        state.exitMonitorTask?.cancel()
        state.exitMonitorTask = nil
        releaseIP(for: id)

        // Stop port forwarding
        if let forwarder = portForwarders.removeValue(forKey: id) {
            Task { await forwarder.stopAll() }
        }

        containers[id] = state

        if autoRemoves(state) {
            removeContainer(id: id)
        }

        notifyStateChange()
    }

    private func gracefulStopContainer(_ lc: LinuxContainer, stopOpts: ContainerStopOptions) async throws {
        // Try to gracefully shut down the process, then force-stop the VM.
        do {
            _ = try await withThrowingTaskGroup(of: ExitStatus.self) { group in
                group.addTask {
                    try await lc.wait()
                }
                group.addTask {
                    try await lc.kill(Signal(rawValue: stopOpts.signal))
                    try await Task.sleep(for: .seconds(stopOpts.timeoutInSeconds))
                    try await lc.kill(Signal(rawValue: SIGKILL))
                    return ExitStatus(exitCode: 137)
                }
                guard let code = try await group.next() else {
                    throw ContainerizationError(
                        .internalError,
                        message: "failed to get exit code from gracefully stopping container"
                    )
                }
                group.cancelAll()
                return code
            }
        } catch {
            log.notice("graceful stop failed, forcing: \(error)")
        }

        // Bring down the VM
        try await lc.stop()
    }

    private static func configureContainer(
        czConfig: inout LinuxContainer.Configuration,
        config: ContainerConfiguration,
        precomputedMounts: [Containerization.Mount],
        precomputedSockets: [UnixSocketConfiguration]
    ) throws {
        czConfig.cpus = config.resources.cpus
        czConfig.memoryInBytes = config.resources.memoryInBytes
        czConfig.sysctl = config.sysctls
        czConfig.virtualization = config.virtualization

        czConfig.mounts.append(contentsOf: precomputedMounts)
        czConfig.sockets.append(contentsOf: precomputedSockets)

        for publishedSocket in config.publishedSockets {
            let socketConfig = UnixSocketConfiguration(
                source: publishedSocket.containerPath,
                destination: publishedSocket.hostPath,
                permissions: publishedSocket.permissions,
                direction: .outOf
            )
            czConfig.sockets.append(socketConfig)
        }

        if config.ssh, let sshSocket = Foundation.ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"] {
            let socketUrl = URL(fileURLWithPath: sshSocket)
            let socketPath = socketUrl.path(percentEncoded: false)
            let attrs = try? FileManager.default.attributesOfItem(atPath: socketPath)
            let permissions = (attrs?[.posixPermissions] as? NSNumber)
                .map { FilePermissions(rawValue: mode_t($0.intValue)) }
            let socketConfig = UnixSocketConfiguration(
                source: socketUrl,
                destination: URL(fileURLWithPath: "/run/host-services/ssh-auth.sock"),
                permissions: permissions,
                direction: .into
            )
            czConfig.sockets.append(socketConfig)
        }

        czConfig.hostname = config.id

        // Only set DNS if explicitly provided by container configuration
        // Setting DNS causes the framework to write /etc/resolv.conf which fails on read-only rootfs
        // If not set, containers will use the host's DNS via the VM network
        if let dns = config.dns, !dns.nameservers.isEmpty {
            czConfig.dns = DNS(
                nameservers: dns.nameservers,
                domain: dns.domain,
                searchDomains: dns.searchDomains,
                options: dns.options
            )
        }

        try Self.configureInitialProcess(czConfig: &czConfig, config: config)
    }

    private static func configureInitialProcess(
        czConfig: inout LinuxContainer.Configuration,
        config: ContainerConfiguration
    ) throws {
        let process = config.initProcess

        czConfig.process.arguments = [process.executable] + process.arguments
        czConfig.process.environmentVariables = process.environment
        czConfig.process.capabilities = try capabilities(from: config.capabilities)

        if config.ssh, Foundation.ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"] != nil {
            let sshEnvVar = "SSH_AUTH_SOCK"
            let sshGuestPath = "/run/host-services/ssh-auth.sock"

            if !czConfig.process.environmentVariables.contains(where: {
                $0.starts(with: "\(sshEnvVar)=")
            }) {
                czConfig.process.environmentVariables.append("\(sshEnvVar)=\(sshGuestPath)")
            }
        }

        czConfig.process.terminal = process.terminal
        czConfig.process.workingDirectory = process.workingDirectory
        czConfig.process.rlimits = process.rlimits.compactMap {
            guard let kind = try? LinuxRLimit.Kind($0.limit) else { return nil }
            return .init(kind: kind, hard: $0.hard, soft: $0.soft)
        }

        switch process.user {
        case .raw(let name):
            czConfig.process.user = .init(
                uid: 0,
                gid: 0,
                umask: nil,
                additionalGids: process.supplementalGroups,
                username: name
            )
        case .id(let uid, let gid):
            czConfig.process.user = .init(
                uid: uid,
                gid: gid,
                umask: nil,
                additionalGids: process.supplementalGroups,
                username: ""
            )
        }
    }

    private static func capabilities(from names: [String]) throws -> Containerization.LinuxCapabilities {
        let capabilities = try capabilitySet(from: names)

        guard !capabilities.isEmpty else {
            return .allCapabilities
        }

        return Containerization.LinuxCapabilities(capabilities: Array(capabilities))
    }

    private static func capabilitySet(from names: [String]) throws -> Set<CapabilityName> {
        var capabilities: Set<CapabilityName> = []

        for name in names {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmedName.isEmpty else {
                continue
            }

            if trimmedName.uppercased() == "ALL" {
                capabilities.formUnion(CapabilityName.allCases)
            } else {
                capabilities.insert(try CapabilityName(rawValue: trimmedName))
            }
        }

        return capabilities
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
    private func notifyStateChange() {
        for callback in stateChangeCallbacks {
            Task { @MainActor in
                callback()
            }
        }
    }
}
