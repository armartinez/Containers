//
//  ContainerRuntime+Plugins.swift
//  Containers
//
//  Plugin process management extension for ContainerRuntime.
//  Manages plugin processes spawned directly as child processes instead of using launchd.
//  This allows the app to work within the macOS sandbox.
//
//  Created by Axel Martinez on 2026/02/08.
//

import ContainerizationError
import Foundation
import Logging

extension ContainerRuntime {

    // MARK: - Plugin Process Management

    /// Register and start a plugin as a child process
    func registerPlugin(
        plugin: Plugin,
        appRoot: URL,
        installRoot: URL,
        containerRoot: URL,
        args: [String],
        instanceId: String
    ) async throws {
        let processKey = "\(plugin.name).\(instanceId)"

        // Check if already running
        if let existing = pluginProcesses[processKey],
            existing.process.isRunning
        {
            logger.info("Plugin already running: \(processKey)")
            return
        }

        logger.info(
            "Starting plugin process: \(plugin.name) with instanceId: \(instanceId)"
        )
        logger.info("Binary path: \(plugin.binaryURL.path)")
        logger.info("Arguments: \(args)")

        let process = Process()
        process.executableURL = plugin.binaryURL
        process.arguments = args

        // Set up environment
        var env = Foundation.ProcessInfo.processInfo.environment
        env["CONTAINER_APP_ROOT"] = appRoot.path
        env["CONTAINER_INSTALL_ROOT"] = installRoot.path

        process.environment = env

        // Set up pipes for output
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Log output from the process
        let pluginName = plugin.name
        let logger = self.logger

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                logger.debug(
                    "[\(pluginName)] stdout: \(str.trimmingCharacters(in: .whitespacesAndNewlines))"
                )
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                logger.info(
                    "[\(pluginName)] stderr: \(str.trimmingCharacters(in: .whitespacesAndNewlines))"
                )
            }
        }

        // Handle process termination
        process.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                self?.handlePluginTermination(
                    processKey: processKey,
                    exitCode: proc.terminationStatus
                )
            }
        }

        do {
            try process.run()
            logger.info(
                "Plugin process started with PID: \(process.processIdentifier)"
            )

            pluginProcesses[processKey] = PluginProcessInfo(
                process: process,
                plugin: plugin,
                instanceId: instanceId,
                standardOutput: stdoutPipe,
                standardError: stderrPipe
            )

            // Give the process a moment to start up and create its XPC server
            try await Task.sleep(for: .milliseconds(500))

        } catch {
            logger.error("Failed to start plugin process: \(error)")
            throw ContainerizationError(
                .internalError,
                message: "Failed to start plugin \(plugin.name): \(error)"
            )
        }
    }

    /// Deregister and stop a plugin process
    func deregisterPlugin(pluginName: String, instanceId: String) {
        let processKey = "\(pluginName).\(instanceId)"

        guard let info = pluginProcesses[processKey] else {
            logger.warning("No running process found for: \(processKey)")
            return
        }

        logger.info("Stopping plugin process: \(processKey)")

        if info.process.isRunning {
            info.process.terminate()

            // Give it a moment to terminate gracefully
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if info.process.isRunning {
                    info.process.interrupt()
                }
            }
        }

        // Clean up pipes
        info.standardOutput?.fileHandleForReading.readabilityHandler = nil
        info.standardError?.fileHandleForReading.readabilityHandler = nil

        pluginProcesses.removeValue(forKey: processKey)
    }

    /// Check if a plugin is running
    func isPluginRunning(pluginName: String, instanceId: String)
        -> Bool
    {
        let processKey = "\(pluginName).\(instanceId)"

        guard let info = pluginProcesses[processKey] else {
            return false
        }

        return info.process.isRunning
    }

    /// Get the PID of a running plugin
    func getPluginPid(
        pluginName: String,
        instanceId: String
    ) -> Int32? {
        let processKey = "\(pluginName).\(instanceId)"

        guard let info = pluginProcesses[processKey], info.process.isRunning
        else {
            return nil
        }

        return info.process.processIdentifier
    }

    /// Stop all running plugin processes
    func stopAllPlugins() {
        logger.info("Stopping all plugin processes...")

        for (key, info) in pluginProcesses {
            logger.info("Stopping: \(key)")
            if info.process.isRunning {
                info.process.terminate()
            }
            info.standardOutput?.fileHandleForReading.readabilityHandler = nil
            info.standardError?.fileHandleForReading.readabilityHandler = nil
        }

        pluginProcesses.removeAll()
    }

    private func handlePluginTermination(processKey: String, exitCode: Int32) {
        logger.info(
            "Plugin process terminated: \(processKey) with exit code: \(exitCode)"
        )

        if let info = pluginProcesses[processKey] {
            info.standardOutput?.fileHandleForReading.readabilityHandler = nil
            info.standardError?.fileHandleForReading.readabilityHandler = nil
        }

        pluginProcesses.removeValue(forKey: processKey)
    }
}
