//
//  Mount.swift
//  Containers
//
//  Created by Axel Martinez on 03/08/2026.
//

import Foundation

enum MountError: LocalizedError {
    case targetMissing
    case targetNotAbsolute
    case sourceNotAbsolute
    case duplicateTarget(String)

    var errorDescription: String? {
        switch self {
        case .targetMissing:
            "Mounts require a target."
        case .targetNotAbsolute:
            "Mount target must be absolute."
        case .sourceNotAbsolute:
            "Mount source must be an absolute host path."
        case .duplicateTarget(let target):
            "A mount already exists at \(target)."
        }
    }
}

struct Mount: Identifiable {
    let id: UUID = UUID()
    var hostURL: URL?
    var containerPath: String = ""
    /// An in-memory mount, which has no host path to share.
    var isTemporary: Bool = false

    var summary: String {
        if !isTemporary && hostURL == nil && trimmedTarget.isEmpty {
            return "New Mount"
        }

        return trimmedTarget.isEmpty
            ? sourceLabel : "\(sourceLabel) -> \(trimmedTarget)"
    }

    var columns: [String] {
        [sourceLabel, trimmedTarget]
    }

    var sourceLabel: String {
        if isTemporary {
            return "Temporary Mount"
        }

        return hostURL?.path ?? "No Source"
    }

    var trimmedTarget: String {
        containerPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
