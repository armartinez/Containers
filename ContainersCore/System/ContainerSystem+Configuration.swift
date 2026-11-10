//
//  ContainerSystem+Configuration.swift
//  Containers
//
//  Created by Axel Martinez on 2026/11/05.
//

import ContainerizationError
import Foundation

extension ContainerSystem {
    /// The settings in a system folder's `config.toml`, read even while the system is stopped.
    ///
    /// - Parameter appRoot: The folder the system keeps its data in.
    /// - Returns: The settings, with the container CLI's defaults for what the file leaves out.
    public func configuration(in appRoot: URL) async -> SystemConfiguration {
        await appRoot.withSecurityScopedAccess {
            await SystemConfiguration.load(appRoot: appRoot, includingInstallDefaults: mode == .cliCompatibility)
        }
    }

    /// Saves a change to the system's settings in the `config.toml` of its folder.
    ///
    /// - Parameters:
    ///   - appRoot: The folder the system keeps its data in.
    ///   - change: The change to make.
    /// - Throws: An error with container CLI compatibility on, where the file is the CLI's, or if it can't be written.
    public func updateConfiguration(in appRoot: URL, _ change: (inout SystemConfiguration) -> Void) async throws {
        guard mode == .default else {
            throw ContainerizationError(
                .unsupported,
                message: "With container CLI compatibility on, these settings are the container CLI’s, in its config.toml."
            )
        }

        var configuration = await configuration(in: appRoot)
        change(&configuration)

        try appRoot.withSecurityScopedAccess {
            try configuration.write(to: appRoot)
        }

        DefaultsStore.configuration = configuration
    }
}
