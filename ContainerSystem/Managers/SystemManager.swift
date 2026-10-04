//
//  SystemManager.swift
//  Containers
//
//  System lifecycle management
//
//  Created by Axel Martinez on 2026/02/08.
//

import Foundation
import Logging
import Observation

/// Public system manager for controlling container system lifecycle
/// This is the main API exposed to the UI layer for system control
@Observable
@MainActor
public final class SystemManager {

    let runtime: ContainerRuntime
    private let logger: Logger
    private var startTask: Task<Void, Error>?

    public var startupError: (any Error)? { runtime.startupError }

    /// Where the system is in its life cycle; `startupError` says why a start failed.
    public enum Status: Equatable {
        case notStarted
        case starting
        case running
        case stopping
        case failed
    }

    public var status: Status {
        if runtime.isStopping { return .stopping }
        if runtime.isStarting { return .starting }
        if runtime.isRunning { return .running }
        if runtime.startupError != nil { return .failed }
        return .notStarted
    }

    /// How far a first start has got with installing what the system needs,
    /// while it installs it; `nil` once there is nothing left to install.
    public var setupProgress: Progress? {
        runtime.setupProgress
    }

    /// Public initializer - creates instance referencing shared runtime
    public init() {
        self.runtime = ContainerRuntime.shared
        self.logger = Logger(label: "app.containers.manager.system")
    }

    #if DEBUG
    /// Internal initializer for testing - allows injection of test runtime
    init(testRuntime: ContainerRuntime) {
        self.runtime = testRuntime
        self.logger = Logger(label: "app.containers.manager.system.test")
    }
    #endif

    // MARK: - Lifecycle Methods

    /// Start the container system.
    /// - Parameter appRoot: Root directory for container data.
    /// - Throws: An error if the runtime cannot initialize prerequisites, storage, services, or networking.
    public func start(appRoot: URL) async throws {
        logger.info("Starting system", metadata: ["appRoot": "\(appRoot.path)"])

        let task = Task { [runtime] in
            try await runtime.start(appRoot: appRoot)
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
    }

    public func cancelStart() {
        logger.info("Cancelling start")
        startTask?.cancel()
    }

    public func diskUsage() async -> Int64? {
        guard let appRoot = try? runtime.getAppRoot() else { return nil }

        return await FileIO.shared.allocatedSize(of: appRoot)
    }

    /// Stop the container system
    public func stop() async throws {
        logger.info("Stopping system")
        try await runtime.stop()
    }
}
