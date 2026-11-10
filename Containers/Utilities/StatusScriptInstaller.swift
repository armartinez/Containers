//
//  StatusScriptInstaller.swift
//  Containers
//
//  Created by Axel Martinez on 2026/10/30.
//

import AppKit
import ContainersCore

/// Installs the script container CLI compatibility asks the CLI's status with.
@MainActor
enum StatusScriptInstaller {
    enum Failure: LocalizedError {
        case noScriptsFolder
        case wrongLocation(URL)

        var errorDescription: String? {
            switch self {
            case .noScriptsFolder:
                "macOS has no Application Scripts folder for Containers."
            case .wrongLocation(let scriptURL):
                "Containers can only run the script from \(scriptURL.deletingLastPathComponent().path), under the name “\(scriptURL.lastPathComponent)”."
            }
        }
    }

    /// The app can't write to its Application Scripts folder, but a save panel the user confirms can.
    ///
    /// - Returns: Whether the script was installed; `false` if the user cancelled.
    static func install(using containerSystem: ContainerSystem) async throws -> Bool {
        guard let scriptURL = ContainerCLI.StatusScript.url else {
            throw Failure.noScriptsFolder
        }

        let panel = NSSavePanel()
        panel.directoryURL = scriptURL.deletingLastPathComponent()
        panel.nameFieldStringValue = scriptURL.lastPathComponent
        panel.canCreateDirectories = false

        if containerSystem.cli.isStatusScriptOutdated {
            panel.prompt = "Update"
            panel.message =
                "The script Containers uses to interact with the container CLI has changed. Replace it here, without renaming it."
        } else {
            panel.prompt = "Install"
            panel.message =
                "Containers is sandboxed, so it uses a script you install to interact with the container CLI. Install it here, without renaming it."
        }

        guard let url = await panel.presentAsSheet() else {
            return false
        }

        guard url.standardizedFileURL == scriptURL.standardizedFileURL else {
            throw Failure.wrongLocation(scriptURL)
        }

        try containerSystem.cli.installStatusScript(at: url)

        return true
    }
}
