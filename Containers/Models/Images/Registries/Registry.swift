//
//  Registry.swift
//  Containers
//
//  Created by Axel Martinez on 01/08/2026.
//

import Foundation

/// The registries offered in the Registry field.
enum Registry: Hashable, CaseIterable, CustomStringConvertible, Sendable {
    case dockerHub

    var description: String {
        switch self {
        case .dockerHub:
            "Docker Hub"
        }
    }

    var provider: any RegistryProvider {
        switch self {
        case .dockerHub:
            DockerHub()
        }
    }
}
