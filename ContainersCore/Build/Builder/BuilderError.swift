//
//  BuilderError.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/09.
//

import Foundation

enum BuilderError: Swift.Error, CustomStringConvertible, Equatable {
    case invalidContinuation
    case imageMissing
    case platformMissing
    case imageNotFound
    case imageNotInContentStore(String)
    case unknownPlatformForImage(String, String)
    case buildComplete
    case buildTimeout

    var description: String {
        switch self {
        case .invalidContinuation:
            return "Failed to create stream continuation"
        case .imageMissing:
            return "Image reference missing in metadata"
        case .platformMissing:
            return "Platform parameter missing in metadata"
        case .imageNotFound:
            return "Image not found in content store"
        case .imageNotInContentStore(let ref):
            return "Image not found in content store: \(ref)"
        case .unknownPlatformForImage(let platform, let ref):
            return "Platform \(platform) for image \(ref) not found"
        case .buildComplete:
            return "Build completed successfully"
        case .buildTimeout:
            return "Build timed out"
        }
    }
}
