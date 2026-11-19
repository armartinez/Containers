//
//  ContainerCLIError+Settings.swift
//  Containers
//
//  Created by Axel Martinez on 2026/11/08.
//

import ContainersCore

extension ContainerCLIError {
    /// Whether only a change in Settings fixes the error, rather than trying again.
    var isFixedInSettings: Bool {
        switch self {
        case .statusScriptNotInstalled, .appRootInUse, .notAppRoot, .noAppRootAccess: true
        case .notInstalled, .unsupportedVersion, .apiServerRunning: false
        }
    }

    /// The error's description, followed by what to change in Settings where that fixes it.
    var message: String {
        let suggestion: String? =
            switch self {
            case .statusScriptNotInstalled:
                "Install the CLI status script in Settings."
            case .appRootInUse:
                "Turn on container CLI compatibility in Settings to work with it, or choose another storage location."
            case .noAppRootAccess:
                "Allow access to it in Settings."
            case .notAppRoot, .notInstalled, .unsupportedVersion, .apiServerRunning:
                nil
            }

        return [errorDescription, suggestion].compactMap { $0 }.joined(separator: " ")
    }
}
