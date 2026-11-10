//
//  ContainerSystem+CLI.swift
//  Containers
//
//  Working in the container CLI's folder, beside its API server.
//
//  Created by Axel Martinez on 2026/11/08.
//

import Foundation

extension ContainerSystem {
    /// Shows the CLI's folder read-only once the CLI starts, while the system is stopped with compatibility on.
    public func watchForAPIServer(in appRoot: URL) {
        guard mode == .cliCompatibility, !isRunning, status != .starting else { return }
        watchFolder(appRoot, onAPIServerStart: .switchToReadOnly)
    }

    func requireOwnFolder(_ appRoot: URL) throws {
        guard ContainerCLI.owns(appRoot) else { return }

        logger.warning("Not starting Containers mode over the CLI's folder")
        startupError = ContainerCLIError.appRootInUse

        throw ContainerCLIError.appRootInUse
    }

    func requireCLICompatibility(over appRoot: URL) async throws -> ContainerCLI.Status {
        do {
            let status = try await cli.supportedStatus()
            try Task.checkCancellation()

            try cli.requireReadableAppRoot(appRoot)

            return status
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logger.warning("Not starting with CLI compatibility", metadata: ["error": "\(error)"])
            startupError = error

            throw error
        }
    }

    /// Stops managing the CLI's folder when its API server starts, and goes on showing it read-only.
    private func switchToReadOnly(appRoot: URL) async {
        guard mode == .cliCompatibility else {
            folderWatcher.stop()
            return
        }

        logger.info("The container CLI started over the system's folder; showing it read-only")

        cancelStart()
        try? await stop()

        // The API server may not be registered yet, so the status script can't be trusted to say it runs.
        isSwitchingToReadOnly = true
        try? await start(appRoot: appRoot)
    }

    /// Stops the system, whose folder the CLI's API server started over, and reports the folder as the CLI's.
    private func stopForAPIServer() async {
        logger.warning("The container CLI started over the system's folder; stopping the system")

        cancelStart()
        try? await stop()

        startupError = ContainerCLIError.appRootInUse
        settleStopped()
    }

    enum APIServerStartResponse {
        case ignore
        case stop
        case switchToReadOnly
    }

    func watchFolder(_ appRoot: URL, onAPIServerStart response: APIServerStartResponse) {
        let onAPIServerStart: (@MainActor @Sendable () async -> Void)? =
            switch response {
            case .ignore: nil
            case .stop: { [weak self] in await self?.stopForAPIServer() }
            case .switchToReadOnly: { [weak self] in await self?.switchToReadOnly(appRoot: appRoot) }
            }

        folderWatcher.watch(appRoot, onAPIServerStart: onAPIServerStart) { [weak self] paths in
            await self?.handleFolderChanges(at: paths)
        }
    }

    /// Acts on the paths, relative to the system's folder, that changed under it.
    private func handleFolderChanges(at paths: [String]) async {
        guard isReadOnly else { return }

        let topLevelNames = Set(paths.compactMap { $0.split(separator: "/").first.map(String.init) })

        if topLevelNames.contains("containers") {
            await reloadSharedContainers()
        }

        // Images and volumes are read from disk whenever they're listed; their views only need
        // telling. The image index is rewritten whenever an image is added or removed.
        if topLevelNames.contains("state.json") {
            lastSharedImageChange = Date()
        }

        if topLevelNames.contains("volumes") {
            lastSharedVolumeChange = Date()
        }
    }
}
