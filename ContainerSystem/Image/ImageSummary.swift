//
//  ImageSummary.swift
//  Containers
//
//  Created by Axel Martinez on 03/10/2026.
//

import Foundation

/// An image as a list shows it: what it is, what it holds for one platform,
/// and whether a container uses it.
public struct ImageSummary {
    public struct Platform {
        public let variant: String?
        public let created: Date
        public let os: String
        public let architecture: String
        public let size: Int64

        public init(variant: String?, created: Date, os: String, architecture: String, size: Int64) {
            self.variant = variant
            self.created = created
            self.os = os
            self.architecture = architecture
            self.size = size
        }
    }

    public static let unknownCreationDate = Date(timeIntervalSince1970: 0)

    public let description: ImageDescription
    /// `nil` unless the list was asked for a platform.
    public let platform: Platform?
    public let variants: [ImageResource.Variant]
    public let isInUse: Bool

    public init(
        description: ImageDescription,
        platform: Platform?,
        variants: [ImageResource.Variant] = [],
        isInUse: Bool
    ) {
        self.description = description
        self.platform = platform
        self.variants = variants
        self.isInUse = isInUse
    }
}
