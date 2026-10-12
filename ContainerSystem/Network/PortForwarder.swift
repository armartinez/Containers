//
//  PortForwarder.swift
//  Containers
//
//  TCP/UDP port forwarding from host to container via vsock.
//  Replaces the SocketForwarder module from the apple/container package.
//

import Containerization
import ContainerizationError
import Foundation
import Logging

/// Manages port forwarding from host TCP/UDP ports to container ports via vsock.
public actor PortForwarder {

    private let log: Logger
    private var forwarders: [String: ActiveForwarder] = [:]

    /// Represents an active port forwarding session.
    private struct ActiveForwarder {
        let id: String
        let hostPort: UInt16
        let containerPort: UInt16
        let proto: PublishProtocol
        let listener: Task<Void, Never>
    }

    public init(log: Logger) {
        self.log = log
    }

    /// Start forwarding one or more host TCP ports to container ports.
    /// - Parameters:
    ///   - publishPort: The port forwarding configuration.
    ///   - container: The running LinuxContainer to forward to.
    /// - Throws: An error if the listener socket cannot be created, bound, or started.
    public func startForwarding(
        publishPort: PublishPort,
        container: LinuxContainer
    ) async throws {
        for i: UInt16 in 0..<publishPort.count {
            let hostPort = publishPort.hostPort + i
            let containerPort = publishPort.containerPort + i
            let id =
                "\(hostPort)-\(containerPort)-\(publishPort.proto.rawValue)"

            guard forwarders[id] == nil else {
                log.warning("Port forwarding already active for \(id)")
                continue
            }

            guard publishPort.proto == .tcp else {
                log.warning(
                    "UDP port forwarding not yet supported, skipping port \(hostPort)"
                )
                continue
            }

            let listener = Task { [log] in
                do {
                    try await Self.tcpForwardLoop(
                        hostPort: hostPort,
                        containerPort: containerPort,
                        hostAddress: publishPort.hostAddress.description,
                        container: container,
                        log: log
                    )
                } catch is CancellationError {
                    // Normal shutdown
                } catch {
                    log.error(
                        "Port forwarding failed for \(hostPort) -> \(containerPort): \(error)"
                    )
                }
            }

            forwarders[id] = ActiveForwarder(
                id: id,
                hostPort: hostPort,
                containerPort: containerPort,
                proto: publishPort.proto,
                listener: listener
            )

            log.info(
                "Started port forwarding: \(hostPort) -> \(containerPort)/\(publishPort.proto.rawValue)"
            )
        }
    }

    /// Stop all port forwarding for a specific container.
    public func stopAll() {
        for (_, forwarder) in forwarders {
            forwarder.listener.cancel()
        }
        forwarders.removeAll()
        log.info("Stopped all port forwarding")
    }

    /// Stop forwarding for a specific port.
    public func stopForwarding(
        hostPort: UInt16,
        containerPort: UInt16,
        proto: PublishProtocol
    ) {
        let id = "\(hostPort)-\(containerPort)-\(proto.rawValue)"
        if let forwarder = forwarders.removeValue(forKey: id) {
            forwarder.listener.cancel()
            log.info(
                "Stopped port forwarding: \(hostPort) -> \(containerPort)/\(proto.rawValue)"
            )
        }
    }

    // MARK: - TCP Forwarding

    /// Creates a TCP listening socket, accepts connections, and forwards each to
    /// the container's port via vsock.
    private static func tcpForwardLoop(
        hostPort: UInt16,
        containerPort: UInt16,
        hostAddress: String,
        container: LinuxContainer,
        log: Logger
    ) async throws {
        let serverFD = socket(AF_INET, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            throw ContainerizationError(
                .internalError,
                message: "Failed to create socket: \(errno)"
            )
        }

        // Allow address reuse
        var reuseAddr: Int32 = 1
        setsockopt(
            serverFD,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuseAddr,
            socklen_t(MemoryLayout<Int32>.size)
        )

        // Bind to address
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = hostPort.bigEndian

        if hostAddress == "0.0.0.0" || hostAddress.isEmpty {
            addr.sin_addr.s_addr = INADDR_ANY
        } else {
            _ = hostAddress.withCString { cStr in
                inet_pton(AF_INET, cStr, &addr.sin_addr)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            Darwin.close(serverFD)
            throw ContainerizationError(
                .internalError,
                message:
                    "Failed to bind to \(hostAddress):\(hostPort): \(errno)"
            )
        }

        guard listen(serverFD, 128) == 0 else {
            Darwin.close(serverFD)
            throw ContainerizationError(
                .internalError,
                message:
                    "Failed to listen on \(hostAddress):\(hostPort): \(errno)"
            )
        }

        // Set non-blocking so we can check for cancellation
        let flags = fcntl(serverFD, F_GETFL)
        _ = fcntl(serverFD, F_SETFL, flags | O_NONBLOCK)

        defer { Darwin.close(serverFD) }

        log.info(
            "Listening on \(hostAddress):\(hostPort) for forwarding to container port \(containerPort)"
        )

        while !Task.isCancelled {
            var clientAddr = sockaddr_in()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)

            let clientFD = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(serverFD, $0, &clientAddrLen)
                }
            }

            if clientFD < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    // No pending connections, sleep briefly and retry
                    try await Task.sleep(for: .milliseconds(50))
                    continue
                }
                if errno == EBADF {
                    // Socket was closed
                    break
                }
                log.warning("Accept failed: \(errno)")
                try await Task.sleep(for: .milliseconds(100))
                continue
            }

            // Handle each connection in a separate task
            Task {
                await Self.handleForwardedConnection(
                    clientFD: clientFD,
                    containerPort: containerPort,
                    container: container,
                    log: log
                )
            }
        }
    }

    /// Handles a single forwarded TCP connection: dials the container's vsock port
    /// and relays data bidirectionally.
    private static func handleForwardedConnection(
        clientFD: Int32,
        containerPort: UInt16,
        container: LinuxContainer,
        log: Logger
    ) async {
        do {
            let vsockHandle = try await container.dialVsock(
                port: UInt32(containerPort)
            )
            let clientHandle = FileHandle(
                fileDescriptor: clientFD,
                closeOnDealloc: true
            )

            // Relay data bidirectionally
            await withTaskGroup(of: Void.self) { group in
                // Client -> Container
                group.addTask {
                    do {
                        while true {
                            let data = clientHandle.availableData
                            guard !data.isEmpty else { break }
                            try vsockHandle.write(contentsOf: data)
                        }
                    } catch {
                        // Connection closed or error
                    }
                    try? vsockHandle.close()
                }

                // Container -> Client
                group.addTask {
                    do {
                        while true {
                            let data = vsockHandle.availableData
                            guard !data.isEmpty else { break }
                            try clientHandle.write(contentsOf: data)
                        }
                    } catch {
                        // Connection closed or error
                    }
                    try? clientHandle.close()
                }
            }
        } catch {
            log.error(
                "Failed to forward connection to container port \(containerPort): \(error)"
            )
            Darwin.close(clientFD)
        }
    }
}
