//
//  KernelService.swift
//  Containers
//
//  Manages kernel binaries for container VMs.
//
//  Created by Axel on 17/3/26.
//

import Containerization
import ContainerizationArchive
import ContainerizationError
import CryptoKit
import Foundation
import Logging

/// Service for handling Linux kernel binaries used by container VMs.
struct KernelService: Sendable {
    private let log: Logger
    private let kernelsRoot: URL

    init(log: Logger, appRoot: URL) throws {
        self.log = log
        self.kernelsRoot = appRoot.appendingPathComponent("kernels")

        try FileManager.default.createDirectory(at: kernelsRoot, withIntermediateDirectories: true)
    }

    /// The link naming each platform's default kernel, so the CLI and the app boot the same kernel
    /// from a shared folder.
    private func defaultKernelLink(for platform: SystemPlatform) -> URL {
        kernelsRoot.appendingPathComponent("default.kernel-\(platform.architecture.rawValue)")
    }

    /// Get the default kernel for the given platform.
    func getDefaultKernel(platform: SystemPlatform) async throws -> Kernel {
        let kernelPath = defaultKernelLink(for: platform).resolvingSymlinksInPath()

        guard FileManager.default.fileExists(atPath: kernelPath.path) else {
            throw ContainerizationError(
                .notFound,
                message: "Default kernel not found for \(platform.architecture.rawValue)"
            )
        }

        return Kernel(path: kernelPath, platform: platform)
    }

    /// Install a kernel binary for the given platform from a tar archive, and make it the
    /// platform's default.
    ///
    /// Reading the kernel out of the archive is tens of megabytes of blocking
    /// I/O, so it runs on this actor rather than on the caller that asked
    /// for it.
    func installKernelFrom(
        tar tarFile: URL,
        kernelFilePath: String,
        platform: SystemPlatform,
        expectedDigest: String? = nil,
        force: Bool = false
    ) async throws {
        let link = defaultKernelLink(for: platform)

        if FileManager.default.fileExists(atPath: link.resolvingSymlinksInPath().path), !force {
            log.info("Kernel already installed for \(platform.architecture.rawValue), skipping")
            return
        }

        if let expectedDigest {
            try Self.verifyDigest(of: tarFile, expected: expectedDigest)
        }

        let kernel = try extractFile(tarFile: tarFile, at: kernelFilePath)
        let destination = kernelsRoot.appendingPathComponent(URL(filePath: kernelFilePath).lastPathComponent)

        try kernel.write(to: destination, options: .atomic)

        // Relative, so the link still resolves if the folder is reached by another path.
        try? FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(
            atPath: link.path,
            withDestinationPath: destination.lastPathComponent
        )

        log.info("Kernel installed at \(destination.path), size: \(kernel.count) bytes")
    }

    /// Checks an archive against a `sha256:<hex>` digest.
    static func verifyDigest(of file: URL, expected: String) throws {
        guard !expected.isEmpty else {
            throw ContainerizationError(.invalidArgument, message: "kernel.digest is required when kernel.url is not the default URL")
        }

        let parts = expected.lowercased().split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)

        guard parts.count == 2, parts[0] == "sha256", parts[1].count == 64, parts[1].allSatisfy(\.isHexDigit) else {
            throw ContainerizationError(.invalidArgument, message: "invalid kernel archive digest '\(expected)'")
        }

        var hasher = SHA256()
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            hasher.update(data: data)
        }

        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()

        guard actual == parts[1] else {
            throw ContainerizationError(
                .invalidState,
                message: "kernel archive digest mismatch: expected sha256:\(parts[1]), got sha256:\(actual)"
            )
        }
    }

    /// Extract a file from an archive, returning its bytes rather than a path.
    private func extractFile(tarFile: URL, at path: String) throws -> Data {
        log.info("Extracting \(path) from archive: \(tarFile.path)")

        var archiveReader = try ArchiveReader(file: tarFile)
        let (entry, extracted) = try archiveReader.extractFile(path: path)

        // If the target file is a symlink, get the data for the actual file
        guard entry.fileType == .symbolicLink, let symlinkRelative = entry.symlinkTarget else {
            return extracted
        }

        // Reopen the archive to traverse from the beginning
        archiveReader = try ArchiveReader(file: tarFile)

        let symlinkTarget = URL(filePath: path).deletingLastPathComponent().appending(path: symlinkRelative)
        let resolvedPath = symlinkTarget.standardized.relativePath

        log.info("Kernel is a symlink to \(symlinkRelative), resolved: \(resolvedPath)")

        let (_, targetData) = try archiveReader.extractFile(path: resolvedPath)

        return targetData
    }
}
