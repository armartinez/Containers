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

/// A manager that starts and stops the container system, and reports its status.
///
/// Start the container system before you use the other managers. The first start installs what the
/// system needs, such as the Linux kernel, and reports it through ``setupProgress``.
@Observable
@MainActor
public final class SystemManager {

    let runtime: ContainerRuntime
    private let logger: Logger
    private var startTask: Task<Void, Error>?

    /// The error that made the last start fail, or `nil` if it didn't fail.
    public var startupError: (any Error)? { runtime.startupError }

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
        /// The last start failed. ``SystemManager/startupError`` describes why.
        case failed
    }

    /// The stage the container system is in.
    public var status: Status {
        if runtime.isStopping { return .stopping }
        if runtime.isStarting { return .starting }
        if runtime.isRunning { return .running }
        if runtime.startupError != nil { return .failed }
        return .notStarted
    }

    /// The progress of installing what the container system needs, such as the Linux kernel and the
    /// init image, while a start installs it.
    ///
    /// This property is `nil` when nothing is being installed.
    public var setupProgress: Progress? {
        runtime.setupProgress
    }

    /// Creates a manager for the shared container system.
    public init() {
        self.runtime = ContainerRuntime.shared
        self.logger = Logger(label: "app.containers.manager.system")
    }

    #if DEBUG
    /// Creates a manager for the given runtime, so tests can use a runtime of their own.
    init(testRuntime: ContainerRuntime) {
        self.runtime = testRuntime
        self.logger = Logger(label: "app.containers.manager.system.test")
    }
    #endif

    // MARK: - Lifecycle Methods

    /// Starts the container system, installing what it needs the first time.
    ///
    /// - Parameter appRoot: The folder where the container system keeps its data.
    /// - Throws: An error if the system can't install what it needs, or start its storage or services.
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

    /// Cancels a start that's in progress, including one another caller began.
    public func cancelStart() {
        logger.info("Cancelling start")
        startTask?.cancel()
    }

    /// Returns the disk space the container system's data uses, in bytes, or `nil` if it isn't running.
    public func diskUsage() async -> Int64? {
        guard let appRoot = try? runtime.getAppRoot() else { return nil }

        return await FileIO.shared.allocatedSize(of: appRoot)
    }

    /// Stops the container system, and every container that's running.
    public func stop() async throws {
        logger.info("Stopping system")
        try await runtime.stop()
    }
}
