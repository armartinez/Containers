//
//  ImageResource.swift
//  Containers
//
//  Created by Axel Martinez on 2026/06/06.
//

import Containerization
import ContainerizationOCI
import Foundation

public struct ImageResource: Codable, Sendable {
    public let configuration: ImageConfiguration
    public let variants: [Variant]

    public var id: String {
        configuration.descriptor.digest.digestHex
    }

    public var name: String {
        configuration.name
    }

    public var creationDate: Date {
        configuration.creationDate
    }

    public struct Variant: Codable, Sendable {
        public let platform: Platform
        public let digest: String
        public let size: Int64
        public let config: ContainerizationOCI.Image

        public init(
            platform: Platform,
            digest: String,
            size: Int64,
            config: ContainerizationOCI.Image
        ) {
            self.platform = platform
            self.digest = digest
            self.size = size
            self.config = config
        }
    }

    public struct ImageConfiguration: Codable, Sendable {
        public let creationDate: Date
        public let name: String
        public let descriptor: Descriptor

        public init(description: ImageDescription, creationDate: Date) {
            self.creationDate = creationDate
            self.name = description.reference
            self.descriptor = description.descriptor
        }

        public init(name: String, descriptor: Descriptor, creationDate: Date) {
            self.creationDate = creationDate
            self.name = name
            self.descriptor = descriptor
        }
    }

    public init(configuration: ImageConfiguration, variants: [Variant]) {
        self.configuration = configuration
        self.variants = variants
    }

    public init(
        name: String,
        descriptor: Descriptor,
        variants: [Variant],
        creationDate: Date
    ) {
        self.configuration = ImageConfiguration(
            name: name,
            descriptor: descriptor,
            creationDate: creationDate
        )
        self.variants = variants
    }
}

extension ImageResource {
    enum CodingKeys: String, CodingKey {
        case id
        case configuration
        case variants
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(configuration, forKey: .configuration)
        try container.encode(variants, forKey: .variants)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.configuration = try container.decode(
            ImageConfiguration.self,
            forKey: .configuration
        )
        self.variants = try container.decode([Variant].self, forKey: .variants)
    }
}
