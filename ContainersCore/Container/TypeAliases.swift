//
//  TypeAliases.swift
//  Containers
//
//  Type aliases for containerization package types used throughout the project.
//

import Containerization
import ContainerizationOCI
import Foundation

/// Alias for Image.Description from the Containerization package.
public typealias ImageDescription = Containerization.Image.Description

// MARK: - Codable conformance for Image.Description

extension Containerization.Image.Description: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case reference
        case descriptor
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let reference = try container.decode(String.self, forKey: .reference)
        let descriptor = try container.decode(
            Descriptor.self,
            forKey: .descriptor
        )
        self.init(reference: reference, descriptor: descriptor)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reference, forKey: .reference)
        try container.encode(descriptor, forKey: .descriptor)
    }
}

extension Containerization.Image.Description:
    @retroactive CustomStringConvertible
{
    public var description: String {
        guard let annotations = self.descriptor.annotations else {
            return self.reference
        }

        if let name = annotations[AnnotationKeys.containerizationImageName] {
            return name
        }

        if let name = annotations[AnnotationKeys.containerdImageName] {
            return name
        }

        if let name = annotations[AnnotationKeys.openContainersImageName] {
            return name
        }

        return self.reference
    }
}

// MARK: - SystemPlatform convenience

extension SystemPlatform {
    /// The current host platform.
    public static var current: SystemPlatform {
        #if arch(arm64)
        return .linuxArm
        #else
        return .linuxAmd
        #endif
    }
}
