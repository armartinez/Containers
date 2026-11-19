//
//  ContainerCLI+FolderWatcher.swift
//  Containers
//
//  Created by Axel Martinez on 2026/11/05.
//

import Foundation

extension ContainerCLI {
    /// Watches a system folder the container CLI may share, for the containers, images and volumes the
    /// CLI makes and removes there, and for its API server starting.
    @MainActor
    final class FolderWatcher {
        private var task: Task<Void, Never>?

        // The task doesn't hold the watcher, so it would otherwise outlive it, still watching.
        deinit {
            task?.cancel()
        }

        /// Watches `appRoot` until ``stop()``, in place of any folder watched before.
        ///
        /// - Parameters:
        ///   - appRoot: The folder to watch.
        ///   - onAPIServerStart: Called once when the CLI's API server starts over the folder, which ends
        ///     the watch, or `nil` to go on watching.
        ///   - onChange: Called with the paths, relative to the folder, that changed under it.
        func watch(
            _ appRoot: URL,
            onAPIServerStart: (@MainActor @Sendable () async -> Void)?,
            onChange: @escaping @MainActor @Sendable ([String]) async -> Void
        ) {
            task?.cancel()

            task = Task {
                await appRoot.withSecurityScopedAccess {
                    for await paths in FolderEvents.changes(under: appRoot) {
                        if let onAPIServerStart, paths.contains(ContainerCLI.apiServerPlistPath) {
                            // A task of its own: stopping the system ends this watch, and its cancellation
                            // would otherwise cut the stop short.
                            Task { await onAPIServerStart() }
                            return
                        }

                        await onChange(paths)
                    }
                }
            }
        }

        func stop() {
            task?.cancel()
            task = nil
        }
    }
}
