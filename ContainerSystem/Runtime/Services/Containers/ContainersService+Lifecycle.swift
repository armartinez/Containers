//
//  ContainersService+Lifecycle.swift
//  Containers
//
//  Booting, starting, stopping and deleting containers, and handling their exits.
//
//  Created by Axel Martinez on 2026/10/24.
//

import Containerization
import ContainerizationError
import ContainerizationExtras
import ContainerizationOS
import Foundation
import Logging

extension ContainersService {
    func bootstrap(id: String, stdio: [FileHandle?]) async throws {
        try await lock(for: id).withLock { _ in
            try await self._bootstrap(id: id, stdio: stdio)
        }
    }

    private func _bootstrap(id: String, stdio: [FileHandle?]) async throws {
        var state = try containerState(for: id)

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

        let bundle = state.bundle ?? Bundle(path: bundlePath(for: id))

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

        // Set up stdio writers, each copying into the container log. A terminal
        // carries stderr on stdout.
        let containerLog = try FileHandle(forWritingTo: containerLogURL)
        let stdout = MultiWriter(handles: [stdio[1], containerLog].compactMap { $0 })
        let stderr =
            config.initProcess.terminal
            ? nil : MultiWriter(handles: [stdio[2], containerLog].compactMap { $0 })
        let stdin = stdio[0].map(FileHandleReader.init(handle:))

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
        // A stop that lands between boot and start waits for the start to
        // finish, or goes first and leaves no virtual machine to start.
        try await lock(for: id).withLock { _ in
            try await self._startProcess(id: id, processID: processID)
        }
    }

    private func _startProcess(id: String, processID: String) async throws {
        var state = try containerState(for: id)

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
                // Booted, but it never got as far as running. A failed start
                // leaves the virtual machine errored, and stopping it again only
                // rethrows that error, so it's let go here. Kept, it would hold
                // the IP address and log handle, and block a delete or restart.
                try? await container.stop()
                await markStopped(id: id)?.stopAll()
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
        let state = try containerState(for: id)

        // A container that exited before anyone waited on it has already torn
        // down its monitor, so the code it left behind is all there is.
        guard let monitor = state.exitMonitorTask else {
            return state.lastExitCode ?? 0
        }

        return try await ExitWaiter().wait(for: monitor)
    }

    func stop(id: String, options: ContainerStopOptions) async throws {
        try await lock(for: id).withLock { _ in
            try await self._stop(id: id, options: options)
        }
    }

    private func _stop(id: String, options: ContainerStopOptions) async throws {
        let initialState = try containerState(for: id)

        if let container = initialState.container {
            // Shown while the container winds down, which can last until the stop timeout.
            containers[id]?.snapshot.status = .stopping
            notifyStateChange()

            do {
                try await gracefulStopContainer(container, stopOpts: options)
            } catch let err as ContainerizationError {
                if err.code != .interrupted {
                    // It is still running, as far as anyone can tell.
                    containers[id]?.snapshot.status = initialState.snapshot.status
                    notifyStateChange()
                    throw err
                }
            } catch {
                log.error("Error during graceful stop of container \(id): \(error)")
            }
        }

        // Stop port forwarding, once the state no longer depends on it.
        await markStopped(id: id)?.stopAll()
    }

    func delete(id: String) async throws {
        // Waits for a boot, start or stop of the same container to finish.
        try await lock(for: id).withLock { _ in
            try await self._delete(id: id)
        }
    }

    private func _delete(id: String) throws {
        let state = try containerState(for: id)

        // A container booted but not yet started still has a virtual machine,
        // which deleting it now would leave running with nothing to stop it.
        if state.snapshot.status == .running || state.container != nil {
            throw ContainerizationError(.invalidState, message: "cannot delete running container")
        }

        removeContainer(id: id)
        notifyStateChange()
    }

    // MARK: - Exit Handling

    private func handleContainerExit(id: String, exitCode: Int32) {
        if let forwarder = markStopped(id: id, exitCode: exitCode) {
            Task { await forwarder.stopAll() }
        }
    }

    /// Records that a container's virtual machine is gone, whether stopped or
    /// exited, and deletes it if it auto-removes. Hands back its port forwarder
    /// for the caller to stop.
    ///
    /// Reads the container's state afresh: a stop runs this after waiting out
    /// the exit, by which time `handleContainerExit` may have kept the exit
    /// code or deleted the container.
    private func markStopped(id: String, exitCode: Int32? = nil) -> PortForwarder? {
        let forwarder = portForwarders.removeValue(forKey: id)

        if var state = containers[id] {
            if let exitCode {
                state.lastExitCode = exitCode
            }

            state.exitMonitorTask?.cancel()
            state.exitMonitorTask = nil
            state.snapshot.status = .stopped
            state.snapshot.networks = []
            state.container = nil
            releaseIP(for: id)

            containers[id] = state

            if autoRemoves(state) {
                removeContainer(id: id)
            }
        }

        notifyStateChange()
        return forwarder
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
}
