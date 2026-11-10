//
//  ReadOnlyContainerService.swift
//  Containers
//
//  The containers in the CLI's folder, while its API server runs them.
//
//  Created by Axel Martinez on 2026/11/06.
//

import Containerization
import Foundation
import Logging

/// A containers service that only reads the containers in the system's folder, beside the CLI's API server, which
/// runs them.
actor ReadOnlyContainerService: ContainerService {
    private let containerRoot: URL
    private let log: Logger
    private var snapshots: [String: ContainerSnapshot]
    private var stateChangeCallbacks: [@Sendable @MainActor () -> Void] = []

    init(appRoot: URL, log: Logger) {
        self.containerRoot = appRoot.appendingPathComponent("containers")
        self.log = log
        self.snapshots = Self.loadSnapshots(root: containerRoot, log: log)
    }

    // Reaping auto-remove containers is the API server's, and whether it runs a container isn't kept on disk.
    private static func loadSnapshots(root: URL, log: Logger) -> [String: ContainerSnapshot] {
        var snapshots: [String: ContainerSnapshot] = [:]

        for (configuration, _) in storedBundles(in: root, log: log) {
            snapshots[configuration.id] = ContainerSnapshot(configuration: configuration, status: .unknown, networks: [])
        }

        return snapshots
    }

    /// Rereads the containers on disk, which the CLI's API server makes and removes.
    func reload() {
        let reloaded = Self.loadSnapshots(root: containerRoot, log: log)

        guard Set(reloaded.keys) != Set(snapshots.keys) else { return }

        snapshots = reloaded

        for callback in stateChangeCallbacks {
            Task { @MainActor in
                callback()
            }
        }
    }

    func addStateChangeCallback(_ callback: @escaping @Sendable @MainActor () -> Void) {
        stateChangeCallbacks.append(callback)
    }

    func list() -> [ContainerSnapshot] {
        snapshots.values.sorted { $0.id < $1.id }
    }

    func withContainerList<T: Sendable>(_ body: @Sendable @escaping ([ContainerConfiguration]) async throws -> T) async throws -> T {
        try await body(snapshots.values.map(\.configuration))
    }

    func create(configuration: ContainerConfiguration, kernel: Kernel, options: ContainerCreateOptions) throws {
        throw ContainerCLIError.apiServerRunning
    }

    func bootstrap(id: String, stdio: [FileHandle?]) throws {
        throw ContainerCLIError.apiServerRunning
    }

    func startProcess(id: String, processID: String) throws {
        throw ContainerCLIError.apiServerRunning
    }

    func wait(id: String) throws -> Int32 {
        throw ContainerCLIError.apiServerRunning
    }

    func stop(id: String, options: ContainerStopOptions) throws {
        throw ContainerCLIError.apiServerRunning
    }

    func delete(id: String) throws {
        throw ContainerCLIError.apiServerRunning
    }

    func exec(id: String, arguments: [String]) throws -> String {
        throw ContainerCLIError.apiServerRunning
    }

    func dial(id: String, port: UInt32) throws -> FileHandle {
        throw ContainerCLIError.apiServerRunning
    }

    func resourceUsage() -> [ContainerResourceUsage] {
        []
    }
}
