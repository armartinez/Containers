//
//  PlatformSelection.swift
//  Containers
//
//  Created by Axel Martinez on 28/06/2026.
//

import ContainerizationOCI
import Foundation

enum PlatformSelection: Hashable, CustomStringConvertible {
    case any
    case platform(Platform)

    var platform: Platform? {
        switch self {
        case .any:
            return nil
        case .platform(let platform):
            return platform
        }
    }

    var description: String {
        switch self {
        case .any:
            return "Any"
        case .platform(let platform):
            return platform.description
        }
    }
}
