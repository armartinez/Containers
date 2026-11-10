//
//  DNSService.swift
//  Containers
//
//  Created by Axel Martinez on 2026/10/30.
//

import Foundation
import Logging

/// Resolves container hostnames for the Mac and the containers, on the addresses the container CLI's DNS servers use,
/// so the resolver files `container system dns create` writes work the same with either running the containers.
actor DNSService {
    static let listenAddress = "127.0.0.1"
    static let hostnamesPort = 2053
    static let localhostPort = 1053

    private let log: Logger
    private var tasks: [Task<Void, Never>] = []

    init(log: Logger) {
        self.log = log
    }

    /// Starts answering for the running containers, and for the localhost domains in a resolver folder.
    ///
    /// - Parameters:
    ///   - containers: The containers to answer for.
    ///   - resolverDirectory: The resolver folder the user gave the app access to, or `nil` without one.
    func start(containers: any ContainerService, resolverDirectory: URL?) {
        guard tasks.isEmpty else { return }

        let hostnames = ContainerDNSHandler { await containers.list() }

        tasks.append(serve(hostnames, port: Self.hostnamesPort, name: "container hostnames"))

        if let resolverDirectory {
            let localhost = LocalhostDNSHandler()

            tasks.append(serve(localhost, port: Self.localhostPort, name: "localhost"))
            tasks.append(Task { await Self.follow(resolverDirectory, into: localhost) })
        }
    }

    func stop() {
        for task in tasks {
            task.cancel()
        }

        tasks = []
    }

    private func serve(_ handler: some DNSHandler & Sendable, port: Int, name: String) -> Task<Void, Never> {
        let log = log

        return Task {
            let server = DNSServer(
                handler: StandardQueryValidator(handler: CompositeResolver(handlers: [handler, NxDomainResolver()])),
                log: log
            )

            log.info("Starting DNS resolver for \(name)", metadata: ["host": "\(Self.listenAddress)", "port": "\(port)"])

            do {
                try await server.run(host: Self.listenAddress, port: port)
            } catch is CancellationError {
                return
            } catch {
                // Most likely the CLI's own server, already listening.
                log.error("DNS resolver for \(name) stopped: \(error)")
            }
        }
    }

    /// Reads the resolver folder now and again whenever its files change, while the task runs.
    private static func follow(_ directory: URL, into handler: LocalhostDNSHandler) async {
        let didAccess = directory.startAccessingSecurityScopedResource()

        defer {
            if didAccess {
                directory.stopAccessingSecurityScopedResource()
            }
        }

        await handler.reload(from: directory)

        for await _ in FolderEvents.changes(under: directory) {
            await handler.reload(from: directory)
        }
    }
}
