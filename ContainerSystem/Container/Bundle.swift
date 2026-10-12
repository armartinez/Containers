//
//  Bundle.swift
//  Containers
//
//  Container bundle that wraps an OCI bundle with container-specific configuration.
//  Stores kernel, init filesystem, container rootfs, and configuration on disk.
//

import Containerization
import ContainerizationError
import Foundation

/// A container bundle that manages on-disk storage for a container's configuration,
/// kernel, init filesystem, and root filesystem.
public struct Bundle: Sendable {

    /// The root path of this bundle on disk.
    public let path: URL

    // Filenames for bundle contents
    private static let configFilename = "config.json"
    private static let kernelFilename = "kernel.json"
    private static let kernelBinaryFilename = "kernel.bin"
    private static let initFsFilename = "initfs.ext4"
    private static let rootFsFilename = "rootfs.json"
    private static let rootFsBlockFilename = "rootfs.ext4"
    private static let optionsFilename = "options.json"
    private static let stateFilename = "state.json"
    private static let bootLogFilename = "vminitd.log"

    /// What a container carries over from one run to the next.
    public struct State: Codable, Sendable {
        public let startedDate: Date?

        public init(startedDate: Date? = nil) {
            self.startedDate = startedDate
        }
    }

    /// Load an existing bundle from the given path.
    public init(path: URL) {
        self.path = path
    }

    /// Load the container configuration from disk.
    public var configuration: ContainerConfiguration {
        get throws {
            try load(filename: Self.configFilename)
        }
    }

    /// Load the kernel configuration from disk.
    public var kernel: Kernel {
        get throws {
            try load(filename: Self.kernelFilename)
        }
    }

    /// The initial filesystem, described from the copy the bundle holds
    /// rather than from a stored descriptor pointing elsewhere.
    public var initialFilesystem: Filesystem {
        Filesystem(
            type: .block(format: "ext4"),
            source: path.appendingPathComponent(Self.initFsFilename).path,
            destination: "/",
            options: ["ro"]
        )
    }

    /// Where the VM writes its console output.
    public var bootLog: URL {
        path.appendingPathComponent(Self.bootLogFilename)
    }

    /// The block holding the container's own root filesystem.
    public var containerRootfsBlock: URL {
        path.appendingPathComponent(Self.rootFsBlockFilename)
    }

    /// Load the container root filesystem configuration from disk.
    public var containerRootfs: Filesystem {
        get throws {
            try load(filename: Self.rootFsFilename)
        }
    }

    /// Create a new container bundle at the given path.
    public static func create(
        path: URL,
        initialFilesystem: Filesystem,
        kernel: Kernel,
        containerConfiguration: ContainerConfiguration,
        options: ContainerCreateOptions? = nil
    ) throws -> Bundle {
        let fm = FileManager.default

        try fm.createDirectory(at: path, withIntermediateDirectories: true)

        let bundle = Bundle(path: path)

        // The kernel binary is copied in, so the container keeps booting the
        // one it was made with even if the original moves or is replaced.
        var kernel = kernel
        let kernelBinary = path.appendingPathComponent(kernelBinaryFilename)
        try fm.copyItem(at: kernel.path, to: kernelBinary)
        kernel.path = kernelBinary

        try bundle.write(filename: kernelFilename, value: kernel)

        // The init filesystem is cloned in for the same reason, which is why
        // `initialFilesystem` reads from the bundle instead of a descriptor.
        guard case .block(let format, _, _) = initialFilesystem.type,
            format == "ext4"
        else {
            throw ContainerizationError(
                .invalidArgument,
                message: "initial filesystem must be an ext4 block"
            )
        }

        try fm.copyItem(
            atPath: initialFilesystem.source,
            toPath: path.appendingPathComponent(initFsFilename).path
        )

        try bundle.write(
            filename: configFilename,
            value: containerConfiguration
        )

        if let options {
            try bundle.write(filename: optionsFilename, value: options)
        }

        return bundle
    }

    /// Point the container root filesystem at a filesystem that already sits
    /// where it is going to stay.
    public func setContainerRootFs(_ fs: Filesystem) throws {
        try write(filename: Self.rootFsFilename, value: fs)
    }

    /// Clone a filesystem into the bundle and make it the container root.
    public func cloneContainerRootFs(
        cloning source: Filesystem,
        readonly: Bool = false
    ) throws {
        var options = source.options
        if readonly, !options.contains("ro") {
            options.append("ro")
        }

        try FileManager.default.copyItem(
            atPath: source.source,
            toPath: containerRootfsBlock.path
        )

        try setContainerRootFs(
            Filesystem(
                type: source.type,
                source: containerRootfsBlock.path,
                destination: source.destination,
                options: options
            )
        )
    }

    /// The options the container was created with, so that what they ask for
    /// still holds on a later run of the app.
    public var createOptions: ContainerCreateOptions {
        get throws {
            try load(filename: Self.optionsFilename)
        }
    }

    /// What the container kept from its last run, empty until it has had one.
    public var state: State {
        (try? load(filename: Self.stateFilename)) ?? State()
    }

    public func setState(_ state: State) throws {
        try write(filename: Self.stateFilename, value: state)
    }

    /// Delete this bundle and all its contents from disk.
    public func delete() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: path.path) {
            try fm.removeItem(at: path)
        }
    }

    /// Write a Codable value to a file in the bundle.
    public func write<T: Codable>(filename: String, value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]

        let data = try encoder.encode(value)
        let file = path.appendingPathComponent(filename)
        try data.write(to: file)
    }

    /// Load a Codable value from a file in the bundle.
    public func load<T: Codable>(filename: String) throws -> T {
        let file = path.appendingPathComponent(filename)

        guard FileManager.default.fileExists(atPath: file.path) else {
            throw ContainerizationError(
                .notFound,
                message: "bundle file not found: \(filename)"
            )
        }

        let data = try Data(contentsOf: file)
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }
}
