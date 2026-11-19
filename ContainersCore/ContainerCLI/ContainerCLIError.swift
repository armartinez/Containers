//
//  ContainerCLIError.swift
//  Containers
//
//  Created by Axel Martinez on 2026/11/05.
//

import Foundation

/// Why the container system can't start over a folder Apple's container CLI uses, or do something beside the CLI.
public enum ContainerCLIError: LocalizedError, Equatable {
    /// The status script that tells whether the CLI is installed and running isn't installed.
    case statusScriptNotInstalled
    /// The CLI isn't installed.
    case notInstalled
    /// The installed CLI, or its running API server, is a version the app doesn't support, or one it can't tell.
    case unsupportedVersion(String?)
    /// The system was asked to start with CLI compatibility over a folder that isn't the CLI's.
    case notAppRoot
    /// The sandbox doesn't let the app read the CLI's folder.
    case noAppRootAccess
    /// Containers mode was asked to start over a folder that is, or lies inside, the CLI's.
    case appRootInUse
    /// The CLI's API server runs over the system's folder, which leaves the system only reading it: nothing
    /// that runs a virtual machine or writes the folder can be done.
    case apiServerRunning

    public var errorDescription: String? {
        switch self {
        case .statusScriptNotInstalled:
            "Containers can’t tell whether the container CLI is installed or running without the CLI status script."
        case .appRootInUse:
            "This folder is the container CLI’s."
        case .notAppRoot:
            "Container CLI compatibility only works in the container CLI’s own folder."
        case .notInstalled:
            "Apple’s container CLI isn’t installed. Install it from github.com/apple/container to use container CLI compatibility."
        case .apiServerRunning:
            "Containers only reads the container CLI’s folder. Make changes with the container CLI, or stop it with “container system stop”, then reload the container system to manage the folder here."
        case .noAppRootAccess:
            "Containers can’t read the container CLI’s folder."
        case .unsupportedVersion(let version?):
            "Containers works with container CLI \(Self.supportedVersions), and this Mac has \(version). Install a supported version, or update Containers."
        case .unsupportedVersion(nil):
            "Containers can’t tell which version of the container CLI is installed. It works with \(Self.supportedVersions)."
        }
    }

    private static var supportedVersions: String {
        ContainerCLI.supportedVersions.sorted().formatted(.list(type: .or))
    }
}
