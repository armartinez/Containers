//
//  ImageItem.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import Containerization
import ContainerizationOCI
import ContainersCore
import Foundation

nonisolated struct ImageItem: Identifiable, Hashable, Equatable, Sendable {
    let name: String
    let tag: String
    let os: String
    let arch: String
    let variant: String
    let sizeInBytes: Int64
    let createdDate: Date
    let indexDigest: String
    /// One per platform in the image's index.
    let variants: [Variant]
    let isInUse: Bool
    let imageDescription: ImageDescription
    var task: ContainerSystemTask.Snapshot?
    /// Whether the image has landed, rather than the row standing in for one
    /// still on its way.
    private(set) var exists = true

    /// A row that only stands for the work of fetching an image.
    var isPending: Bool {
        task != nil && !exists
    }

    var id: String {
        if let task {
            return task.id
        }

        // The reference is what the work that fetches an image knows it by,
        // so the row it arrives in is the row it was being fetched in. What
        // has no reference to be known by — an image left behind by a build
        // that has been retagged — keeps to its digest.
        return Self.identity(for: imageDescription.reference)
            ?? indexDigest + createdDate.description
    }

    /// The reference as the registry knows it, which is how an image arriving
    /// is recognised as the one that was asked for.
    static func identity(for reference: String) -> String? {
        guard !reference.isEmpty, !reference.contains("<none>") else {
            return nil
        }

        return (try? Reference.normalized(reference).description) ?? reference
    }

    init(_ summary: ImageSummary) {
        self.init(
            summary.description,
            variant: summary.platform?.variant,
            created: summary.platform?.created,
            os: summary.platform?.os,
            architecture: summary.platform?.architecture,
            isInUse: summary.isInUse,
            sizeInBytes: summary.platform?.size,
            variants: summary.variants.map(Variant.init)
        )
    }

    /// Initialize from ImageDescription (simplified, without full image details)
    init(
        _ description: ImageDescription,
        variant: String? = nil,
        created: Date? = nil,
        os: String? = nil,
        architecture: String? = nil,
        isInUse: Bool,
        sizeInBytes: Int64? = nil,
        variants: [Variant] = []
    ) {
        self.imageDescription = description

        let (name, tag) = Self.nameAndTag(from: description.reference)
        self.name = name
        self.tag = tag

        self.indexDigest = description.digest
        self.variants = variants
        self.os = os ?? Platform.current.os
        self.arch = architecture ?? Platform.current.architecture
        self.variant = variant ?? ""
        self.sizeInBytes = sizeInBytes ?? description.descriptor.size
        self.createdDate = created ?? ImageSummary.unknownCreationDate
        self.isInUse = isInUse
    }

    /// A row for an image that is still arriving, which has no digest of its
    /// own to be known by until it has.
    init(pending task: ContainerSystemTask.Snapshot) {
        self.imageDescription = ImageDescription(
            reference: task.title,
            descriptor: Descriptor(mediaType: "", digest: "", size: 0)
        )

        let (name, tag) = Self.nameAndTag(from: task.title)

        self.name = name
        self.tag = tag
        self.indexDigest = ""
        self.variants = []
        self.os = Platform.current.os
        self.arch = Platform.current.architecture
        self.variant = ""
        self.sizeInBytes = 0
        self.createdDate = ImageSummary.unknownCreationDate
        self.isInUse = false
        self.task = task
        self.exists = false
    }

    /// What an image with no tag is shown as wherever it is named in full.
    private static let noTag = "<none>"

    var hasTag: Bool { tag != Self.noTag }

    /// The name with its tag, where it has one.
    var displayName: String { hasTag ? "\(name):\(tag)" : name }

    private static func nameAndTag(from reference: String) -> (String, String) {
        guard
            let parsed = try? ContainerizationOCI.Reference.parse(reference)
        else {
            return (reference, noTag)
        }

        return (parsed.name, parsed.tag ?? noTag)
    }

    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(indexDigest)
        hasher.combine(task)
    }

    // Equatable conformance
    static func == (lhs: ImageItem, rhs: ImageItem) -> Bool {
        lhs.indexDigest == rhs.indexDigest
            && lhs.variants == rhs.variants
            && lhs.task == rhs.task
    }
}

extension ImageItem {
    nonisolated struct Variant: Hashable, Sendable {
        let platform: Platform
        let digest: String
        let size: Int64

        init(_ variant: ImageResource.Variant) {
            self.platform = variant.platform
            self.digest = variant.digest
            self.size = variant.size
        }
    }
}

// MARK: - Display Formatting

extension ImageItem {
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeInBytes, countStyle: .file)
    }

    var formattedOS: String {
        os.localizedCapitalized
    }

    var formattedCreated: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdDate)
    }
}
