//
//  ImageManager.swift
//  Containers
//
//  Manager for image operations
//
//  Created by Axel Martinez on 2026/02/08.
//

import Containerization
import ContainerizationError
import ContainerizationOCI
import ContainerizationOS
import Foundation
import Logging
import NIO
import Observation

/// Manages image operations.
/// Create instances via public init() - automatically references shared runtime.
@Observable
@MainActor
public final class ImageManager {
    /// Internal runtime reference (hidden from UI)
    let runtime: ContainerRuntime

    private let logger: Logger

    /// Public initializer - creates instance referencing shared runtime
    public init() {
        self.runtime = ContainerRuntime.shared
        var logger = Logger(label: "app.containers.manager.image")
        logger.logLevel = .info
        self.logger = logger
    }

    #if DEBUG
    /// Internal initializer for testing - allows injection of test runtime
    init(testRuntime: ContainerRuntime) {
        self.runtime = testRuntime
        var logger = Logger(label: "app.containers.manager.image.test")
        logger.logLevel = .debug
        self.logger = logger
    }
    #endif

    // MARK: - Public API

    /// `includeVariants` reads the manifest and config of every platform in
    /// each image's index, which `list` otherwise skips.
    public func list(
        platform: Platform? = nil,
        includeVariants: Bool = false
    ) async throws -> [ImageSummary] {
        let service = try await runtime.getImagesService()
        let containersService = try await runtime.getContainersService()
        let images = try await service.list().filter {
            !Self.isInfraImage(name: $0.reference)
        }
        let usedImageDigests = Set(
            await containersService.list().map { $0.configuration.image.digest }
        )

        guard let platform else {
            return images.map {
                ImageSummary(description: $0, platform: nil, isInUse: usedImageDigests.contains($0.digest))
            }
        }

        let imageStore = try await getImageStore()
        var items: [ImageSummary] = []

        for description in images {
            do {
                let image = try await imageStore.get(reference: description.reference)
                let summary = try await self.summary(for: image, platform: platform)
                let variants = includeVariants ? try await self.variants(of: image) : []
                let item = ImageSummary(
                    description: description,
                    platform: summary,
                    variants: variants,
                    isInUse: usedImageDigests.contains(description.digest)
                )

                items.append(item)
            } catch {
                let item = ImageSummary(
                    description: description,
                    platform: Self.fallbackSummary(for: description, platform: platform),
                    isInUse: usedImageDigests.contains(description.digest)
                )

                items.append(item)
            }
        }

        return items
    }

    public func inspect(image: ImageDescription) async throws -> ImageResource {
        let storedImage = try await getStoredImage(reference: image.reference)
        let index = try await storedImage.index()
        let descriptor = resolvedDescriptor(for: image.descriptor, in: index)
        let variants = try await self.variants(of: storedImage, in: index)

        return ImageResource(
            name: image.reference,
            descriptor: descriptor,
            variants: variants,
            creationDate: Self.creationDate(from: variants)
        )
    }

    public func pull(
        reference: String,
        platform: Platform? = .current,
        scheme: RequestScheme = .auto,
        progress: Progress? = nil
    ) async throws {
        let service = try await runtime.getImagesService()
        let processedReference = try Reference.normalized(reference).description
        let insecure = scheme == .http

        logger.info("Pulling image: \(processedReference)")

        let progress = progress ?? Progress(parent: nil)
        progress.totalUnitCount = 2

        let imageDescription = try await progress.performStep("Fetching image") { step in
            try await service.pull(
                reference: processedReference,
                platform: platform,
                insecure: insecure,
                progressUpdate: step.updateHandler()
            )
        }

        try Task.checkCancellation()

        logger.info("Unpacking image")

        try await progress.performStep("Unpacking image") { step in
            try await service.unpack(
                description: imageDescription,
                platform: platform,
                progressUpdate: step.updateHandler()
            )
        }

        logger.info("Image pulled successfully: \(processedReference)")
    }

    public func build(
        dockerFile: URL,
        contextDirectory: URL,
        tag: String,
        cpus: Int64 = 2,
        memory: UInt64 = 1024.mib(),
        vSockPort: UInt32 = 8088,
        outputs: [BuildImageOutputConfiguration] = [.init(type: .tar, additionalFields: [])],
        platforms: Set<Platform> = [Platform.current],
        buildArguments: [KeyValue] = [],
        labels: [KeyValue] = [],
        noCache: Bool = false,
        targetStage: String = "",
        cacheIn: [String] = [],
        cacheOut: [String] = [],
        progress: Progress? = nil
    ) async throws {
        let containersService = try await runtime.getContainersService()
        let imagesService = try await runtime.getImagesService()
        let appRoot = try runtime.getAppRoot()
        let contentStore = try runtime.getContentStore()

        logger.info("Building image from Dockerfile")

        let didAccessDockerFile = dockerFile.startAccessingSecurityScopedResource()
        let didAccessContextDirectory = contextDirectory.startAccessingSecurityScopedResource()

        defer {
            if didAccessContextDirectory {
                contextDirectory.stopAccessingSecurityScopedResource()
            }
            if didAccessDockerFile {
                dockerFile.stopAccessingSecurityScopedResource()
            }
        }

        let tag = tag.isEmpty ? UUID().uuidString.lowercased() : tag

        // STEP 1: Generate buildID and create export directory FIRST
        let dockerFileData = try await FileIO.shared.contents(of: dockerFile)
        let exportPath = appRoot.appendingPathComponent(".build")
        let id = UUID().uuidString

        // Create the buildID subdirectory for exports BEFORE starting builder
        // This ensures the directory exists when virtiofs mounts are established
        let buildIDDir = exportPath.appendingPathComponent(id)
        try FileManager.default.createDirectory(
            at: buildIDDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Set permissions to 777 to ensure BuildKit (root) can write
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: buildIDDir.path)

        // Create a session directory for this build's context
        let buildSessionDir = exportPath.appendingPathComponent("session-\(id)")
        try FileManager.default.createDirectory(
            at: buildSessionDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let exportDestination = buildIDDir.appendingPathComponent("out.tar")

        // STEP 2: Start/restart the builder NOW with the directory already in place
        let builderController = BuilderController()

        let progress = progress ?? Progress(parent: nil)
        progress.totalUnitCount = 3

        try await progress.performStep("Starting builder") { step in
            try await builderController.restart(cpus: cpus, memory: memory, progress: step)
        }

        // STEP 3: Connect to the (re)started builder
        let timeout: Duration = .seconds(120)
        let buildkitId = BuilderController.builderContainerId

        let builder: Builder = try await withThrowingTaskGroup(of: Builder.self) { group in
            defer {
                group.cancelAll()
            }

            group.addTask { [self] in
                for _ in 0..<10 {
                    do {
                        self.logger.info("Getting Builder container")

                        // Check if builder container exists and is running
                        let containerList = await containersService.list()
                        guard
                            let builderContainer = containerList.first(where: {
                                $0.configuration.id == buildkitId
                            })
                        else {
                            throw ContainerizationError(.notFound, message: "Builder container not found")
                        }

                        guard builderContainer.status == .running else {
                            throw ContainerizationError(
                                .invalidState,
                                message: "Builder container not running"
                            )
                        }

                        self.logger.info("Dialing Builder...")

                        let fileHandle = try await containersService.dial(id: buildkitId, port: vSockPort)
                        let threadGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

                        // Use SandboxedBuilder to avoid XPC-based ClientImage calls
                        let builder = try Builder(
                            socket: fileHandle,
                            group: threadGroup,
                            imagesService: imagesService,
                            contentStore: contentStore
                        )

                        // If this call succeeds, then BuildKit is running.
                        let _ = try await builder.info()

                        return builder
                    } catch {
                        // wait (seconds) for builder to start listening on vSock
                        try await Task.sleep(for: .seconds(5))

                        continue
                    }
                }

                throw ContainerizationError(.timeout, message: "Failed to connect to builder")
            }

            group.addTask {
                try await Task.sleep(for: timeout)

                throw ContainerizationError(.timeout, message: "Timeout waiting for connection to builder")
            }

            guard let builder = try await group.next() else {
                throw ContainerizationError(.timeout, message: "Failed to connect to builder")
            }

            return builder
        }

        // Copy context directory to a temporary location accessible by the builder
        // This is necessary because sandboxed apps can't directly share user-selected directories with the VM
        let tempContextDir = buildSessionDir.appendingPathComponent("context")

        logger.info("Copying context directory from: \(contextDirectory.path)")
        logger.info("Copying context directory to: \(tempContextDir.path)")

        do {
            try await FileIO.shared.copyItem(at: contextDirectory, to: tempContextDir)
            logger.info("Context directory copied successfully")
        } catch {
            logger.error("Failed to copy context directory: \(error)")
            throw error
        }

        defer {
            try? FileManager.default.removeItem(at: buildSessionDir)
            try? FileManager.default.removeItem(at: exportDestination)
        }

        let imageName: String = try {
            let parsedReference = try Reference.parse(tag)
            parsedReference.normalize()

            return parsedReference.description
        }()

        let exports: [Builder.BuildExport] = try outputs.map { output in
            try output.verify()

            var export = output.buildExport

            // Set destination to host path where BuildKit will write the export
            // Use flat file structure to avoid virtiofs subdirectory sync issues
            if export.destination == nil {
                export.destination = exportDestination
            }

            return export
        }

        var quiet = true

        #if DEBUG
        quiet = false
        #endif

        // What the builder says is only shown as progress while the build
        // runs; a build that fails is when it is worth having kept.
        let transcript = BuildTranscript()

        try await progress.performStep("Building image") { step in
            let config = Builder.BuildConfig.init(
                id: id,
                contentStore: contentStore,
                args: buildArguments.map { "\($0.key)=\($0.value)" },
                contextDir: tempContextDir.path,
                dockerfile: dockerFileData,
                labels: labels.map { "\($0.key)=\($0.value)" },
                noCache: noCache,
                platforms: [Platform](platforms),
                terminal: nil,
                tags: [imageName],
                target: targetStage,
                quiet: quiet,
                exports: exports,
                cacheIn: cacheIn,
                cacheOut: cacheOut,
                statusUpdate: { [step, transcript] line in
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

                    if !trimmed.isEmpty {
                        step.localizedAdditionalDescription = trimmed.components(separatedBy: .newlines).last
                    }

                    await MainActor.run {
                        transcript.append(line)
                    }
                }
            )

            logger.info("Starting sandboxed build with config: buildID=\(id), contextDir=\(tempContextDir.path)")

            // Use sandboxed builder which handles image resolution without XPC
            do {
                try await builder.build(config)
            } catch {
                throw BuildFailure(
                    message: (error as? ContainerizationError)?.message ?? error.localizedDescription,
                    transcript: transcript.text
                )
            }
        }

        logger.info("Build completed successfully")

        // Currently, only a single export can be specified.
        for exp in exports {
            switch exp.type {
            case BuildImageOutputConfiguration.BuildType.oci.rawValue:
                try Task.checkCancellation()

                guard let dest = exp.destination else {
                    throw ContainerizationError(.invalidArgument, message: "dest is required \(exp.rawValue)")
                }

                guard FileManager.default.fileExists(atPath: dest.path) else {
                    throw ContainerizationError(
                        .notFound,
                        message: "Build output was not created at \(dest.path)"
                    )
                }

                let extractedLayoutDirectory =
                    buildSessionDir
                    .appendingPathComponent("oci-layout")
                try await FileIO.shared.extractArchive(at: dest, to: extractedLayoutDirectory)

                let (imageDescriptions, _) = try await imagesService.load(
                    from: extractedLayoutDirectory,
                    force: false
                )

                try await progress.performStep("Unpacking built image") { step in
                    let update = step.updateHandler()

                    for imageDesc in imageDescriptions {
                        try Task.checkCancellation()

                        try await imagesService.unpack(
                            description: imageDesc,
                            platform: Platform?.none,
                            progressUpdate: update
                        )
                    }
                }

            case BuildImageOutputConfiguration.BuildType.tar.rawValue:
                guard let dest = exp.destination else {
                    throw ContainerizationError(.invalidArgument, message: "destination is required.")
                }

                let tarURL = exportDestination

                try await FileIO.shared.moveItem(at: tarURL, to: dest)

            case BuildImageOutputConfiguration.BuildType.local.rawValue:
                guard let dest = exp.destination else {
                    throw ContainerizationError(.invalidArgument, message: "destination is required.")
                }

                let localDir = buildSessionDir.appendingPathComponent("local")

                guard FileManager.default.fileExists(atPath: localDir.path)
                else {
                    throw ContainerizationError(.invalidArgument, message: "expected local output not found")
                }

                try await FileIO.shared.copyItem(at: localDir, to: dest)
            default:
                throw ContainerizationError(.invalidArgument, message: "invalid exporter.")
            }
        }

        logger.info("Image built successfully: \(tag)")
    }

    public func save(images: [ImageDescription], platform: Platform = .current, outputURL: URL) async throws {
        let service = try await runtime.getImagesService()

        logger.info("Saving \(images.count) image(s)")

        let references: [String] = images.map(\.reference)
        let stagingDirectory = FileManager.default.temporaryDirectory
            .appending(path: "oci-layout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: stagingDirectory)
        }

        try await service.save(references: references, out: stagingDirectory, platform: platform)

        try await FileIO.shared.writeArchive(directory: stagingDirectory, to: outputURL)

        logger.info("Saved \(images.count) image(s)")
    }

    /// - Returns: The images the archive held, which is only known once it
    ///   has been read.
    @discardableResult
    public func load(
        tar: URL,
        force: Bool = false,
        progress: Progress? = nil
    ) async throws -> [ImageDescription] {
        let service = try await runtime.getImagesService()
        let didAccessTar = tar.startAccessingSecurityScopedResource()
        defer {
            if didAccessTar {
                tar.stopAccessingSecurityScopedResource()
            }
        }

        var isDirectory: ObjCBool = false
        guard
            FileManager.default.fileExists(atPath: tar.path, isDirectory: &isDirectory)
        else {
            throw ContainerizationError(.invalidArgument, message: "File does not exist")
        }

        logger.info("Loading image from: \(tar.lastPathComponent)")

        let progress = progress ?? Progress(parent: nil)
        progress.totalUnitCount = 2

        let source: URL
        let stagingDirectory: URL?

        if isDirectory.boolValue {
            source = tar
            stagingDirectory = nil
        } else {
            let extractedDirectory = FileManager.default.temporaryDirectory
                .appending(path: "oci-layout-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: extractedDirectory, withIntermediateDirectories: true)

            let rejectedMembers = try await FileIO.shared
                .extractArchive(at: tar, to: extractedDirectory)

            if !rejectedMembers.isEmpty && !force {
                try? FileManager.default.removeItem(at: extractedDirectory)
                let rejectedList = rejectedMembers.joined(separator: ", ")
                throw ContainerizationError(
                    .invalidArgument,
                    message: "Cannot load tar image with rejected paths: \(rejectedList)"
                )
            }

            source = extractedDirectory
            stagingDirectory = extractedDirectory
        }

        defer {
            if let stagingDirectory {
                try? FileManager.default.removeItem(at: stagingDirectory)
            }
        }

        let loaded = try await progress.performStep("Loading tar archive") { _ in
            try await service.load(from: source, force: force)
        }

        logger.info("Unpacking images")

        try await progress.performStep("Unpacking image") { step in
            let update = step.updateHandler()

            for imageDescription in loaded.0 {
                try await service.unpack(
                    description: imageDescription,
                    platform: Platform?.none,
                    progressUpdate: update
                )
            }
        }

        logger.info("Images loaded successfully")

        return loaded.0
    }

    public func delete(images: [ImageDescription]) async throws {
        let service = try await runtime.getImagesService()

        logger.info("Deleting \(images.count) image(s)")

        var failed: [(String, Error)] = []
        var deleted: [String] = []
        var didDeleteAnyImage = false

        for image in images {
            guard !Self.isInfraImage(name: image.reference) else {
                continue
            }
            do {
                try await service.delete(reference: image.reference, garbageCollect: false)
                didDeleteAnyImage = true
                deleted.append(image.reference)
                logger.info("Image deleted: \(image.reference)")
            } catch {
                logger.error("Failed to delete image \(image.reference): \(error)")
                failed.append((image.reference, error))
            }
        }

        // A build is reported against the image it was making, so both go
        // with the image itself.
        await ReportManager(runtime: runtime).remove(named: deleted, ofKind: [.image, .build])

        if !failed.isEmpty {
            let failures = (failed.map({ "\($0.0): \($0.1)" })).joined(separator: "\n")
            let message = "failed to delete one or more images: \n\(failures))"

            throw ContainerizationError(.internalError, message: message)
        }

        if didDeleteAnyImage {
            logger.info("Images deleted successfully")
        }
    }

    public func getImageLayers(imageReference: String, platform: Platform) async throws -> [ImageLayer] {
        let appRoot = try runtime.getAppRoot()
        let imagesDir = appRoot.appendingPathComponent("images")

        logger.info("Getting layer information for image: \(imageReference)")

        let imageStore = try ImageStore(path: imagesDir)
        let image = try await imageStore.get(reference: imageReference)

        // Get both manifest (for layer sizes) and image config (for history/commands)
        let manifest = try await image.manifest(for: platform)
        let imageData = try await image.config(for: platform)

        var layers: [ImageLayer] = []
        let history = imageData.history ?? []
        var layerIndex = 0

        if history.isEmpty {
            layers = manifest.layers.map { layer in
                ImageLayer(
                    digest: layer.digest,
                    size: layer.size,
                    createdBy: nil,
                    comment: "Media type: \(layer.mediaType)",
                    emptyLayer: false
                )
            }
        } else {
            for historyEntry in history {
                let isEmptyLayer = historyEntry.emptyLayer ?? false
                let layer =
                    isEmptyLayer || layerIndex >= manifest.layers.count
                    ? nil : manifest.layers[layerIndex]

                if !isEmptyLayer {
                    layerIndex += 1
                }

                layers.append(
                    ImageLayer(
                        digest: layer?.digest,
                        size: layer?.size ?? 0,
                        createdBy: historyEntry.createdBy,
                        comment: historyEntry.comment
                            ?? layer.map { "Media type: \($0.mediaType)" },
                        emptyLayer: isEmptyLayer
                    )
                )
            }

            if layerIndex < manifest.layers.count {
                layers.append(
                    contentsOf: manifest.layers[layerIndex...].map { layer in
                        ImageLayer(
                            digest: layer.digest,
                            size: layer.size,
                            createdBy: nil,
                            comment: "Media type: \(layer.mediaType)",
                            emptyLayer: false
                        )
                    }
                )
            }
        }

        logger.info("Found \(layers.count) history entries for image: \(imageReference)")

        return layers.reversed()
    }

    // MARK: - Private Helper Methods (moved from Utility)

    private func getStoredImage(reference: String) async throws -> Containerization.Image {
        let imageStore = try await getImageStore()
        return try await imageStore.get(reference: reference)
    }

    private func getImageStore() async throws -> ImageStore {
        let appRoot = try runtime.getAppRoot()
        let imagesDir = appRoot.appendingPathComponent("images")
        return try ImageStore(path: imagesDir)
    }

    /// Mirrors `ClientImage.toImageResource` in apple/container: one variant
    /// per platform manifest in the index, skipping any whose manifest or
    /// config can't be read.
    private func variants(
        of image: Containerization.Image,
        in index: Index? = nil
    ) async throws -> [ImageResource.Variant] {
        let index = if let index { index } else { try await image.index() }
        var variants: [ImageResource.Variant] = []

        for manifestDescriptor in index.manifests {
            guard let platform = manifestDescriptor.platform else {
                continue
            }

            do {
                let config = try await image.config(for: platform)
                let manifest = try await image.manifest(for: platform)
                let size =
                    manifestDescriptor.size + manifest.config.size
                    + manifest.layers.reduce(0) { $0 + $1.size }
                let variant = ImageResource.Variant(
                    platform: platform,
                    digest: manifestDescriptor.digest,
                    size: size,
                    config: config
                )

                variants.append(variant)
            } catch {
                continue
            }
        }

        return variants
    }

    private func summary(
        for image: Containerization.Image,
        platform: Platform
    ) async throws -> ImageSummary.Platform {
        let imageData = try await image.config(for: platform)
        let manifest = try await image.manifest(for: platform)

        let createdDate: Date = {
            guard let createdString = imageData.created, let date = Self.date(from: createdString) else {
                return ImageSummary.unknownCreationDate
            }
            return date
        }()

        let size = manifest.config.size + manifest.layers.reduce(0) { $0 + $1.size }

        return ImageSummary.Platform(
            variant: platform.variant,
            created: createdDate,
            os: platform.os,
            architecture: platform.architecture,
            size: size
        )
    }

    private func resolvedDescriptor(for descriptor: Descriptor, in index: Index) -> Descriptor {
        let isIndirect = descriptor.annotations?[AnnotationKeys.containerizationIndexIndirect]?.lowercased()
        guard let isIndirect,
            ["1", "true"].contains(isIndirect),
            let firstManifest = index.manifests.first
        else {
            return descriptor
        }

        return firstManifest
    }

    private static func creationDate(from variants: [ImageResource.Variant]) -> Date {
        for variant in variants {
            guard let created = variant.config.created, let date = date(from: created) else {
                continue
            }

            return date
        }

        return ImageSummary.unknownCreationDate
    }

    private static func fallbackSummary(
        for description: ImageDescription,
        platform: Platform
    ) -> ImageSummary.Platform {
        ImageSummary.Platform(
            variant: platform.variant,
            created: ImageSummary.unknownCreationDate,
            os: platform.os,
            architecture: platform.architecture,
            size: description.descriptor.size
        )
    }

    private static func date(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: string) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private static let infraImages = [
        DefaultsStore.get(key: .defaultBuilderImage),
        DefaultsStore.get(key: .defaultInitImage),
    ]

    private static func isInfraImage(name: String) -> Bool {
        for infraImage in infraImages {
            if name == infraImage {
                return true
            }
        }
        return false
    }
}

public struct BuildImageOutputConfiguration {
    // Public initializer to allow usage in default argument values
    public init(type: BuildType, destinationDirectory: URL? = nil, additionalFields: [KeyValue] = []) {
        self.type = type
        self.destinationDirectory = destinationDirectory
        self.additionalFields = additionalFields
    }

    public enum BuildType: String, Identifiable {
        case oci
        case tar
        case local

        public var id: String {
            self.rawValue
        }

        public var description: String {
            switch self {
            case .oci:
                "Export an OCI(Open Container Initiative)."
            case .tar:
                "Exports files as a tar archive."
            case .local:
                "Exports files to a local directory."
            }
        }

        public var title: String {
            switch self {

            case .oci:
                "OCI"
            case .tar:
                "tar"
            case .local:
                "local"
            }
        }
    }

    public let type: BuildType

    // required for local and tar
    // for OCi, will use a temporary URL specific for the build
    public let destinationDirectory: URL?

    private var destination: URL? {
        switch self.type {
        case .local:
            destinationDirectory?.appending(path: "\(Date().ISO8601Format()).tar")
        case .tar:
            destinationDirectory?.appending(path: "\(Date().ISO8601Format()).tar")
        case .oci:
            nil
        }
    }

    public let additionalFields: [KeyValue]

    private static func keyValueString(key: String, value: String) -> String {
        "\(key)=\(value)"
    }

    var buildExport: Builder.BuildExport {
        var rawInput = Self.keyValueString(key: "type", value: type.rawValue)

        if let destination {
            rawInput = "\(rawInput),\(Self.keyValueString(key: "dest", value: destination.path(percentEncoded: true)))"
        }

        if !additionalFields.isEmpty {
            let additionalFieldString = additionalFields.map {
                "\($0.key)=\($0.value)"
            }.joined(separator: ",")
            rawInput = "\(rawInput),\(additionalFieldString)"
        }

        let additionalFieldsDict = additionalFields.reduce(into: [String: String]()) { dict, item in
            dict[item.key] = item.value
        }

        return .init(
            type: type.rawValue,
            destination: destination,
            additionalFields: additionalFieldsDict,
            rawValue: rawInput
        )
    }

    public func verify() throws {
        guard let destinationDirectory = self.destinationDirectory else {
            if self.type == .oci {
                return
            }

            throw ContainerizationError(
                .invalidArgument,
                message: "Destination required for output type \(self.type.rawValue)"
            )
        }

        if self.type == .oci {
            throw ContainerizationError(.invalidArgument, message: "Destination cannot be specified for OCI.")

        }

        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: destinationDirectory.absoluteString) else {
            throw ContainerizationError(.invalidArgument, message: "Destination directory does not exist.")
        }

        if !destinationDirectory.isDirectory {
            throw ContainerizationError(
                .invalidArgument,
                message: "Specified Destination is not a directory."
            )
        }
    }
}

/// What the builder said while a build ran, kept in case it fails.
@MainActor
private final class BuildTranscript {
    private var lines: [String] = []

    var text: String {
        lines.joined(separator: "\n")
    }

    func append(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return }

        lines.append(trimmed)
    }
}
