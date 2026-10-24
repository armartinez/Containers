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
import Foundation
import Logging

/// Service for handling Linux kernel binaries used by container VMs.
actor KernelService {
    private let log: Logger
    private let kernelsRoot: URL

    init(log: Logger, appRoot: URL) throws {
        self.log = log
        self.kernelsRoot = appRoot.appendingPathComponent("kernels")

        try FileManager.default.createDirectory(at: kernelsRoot, withIntermediateDirectories: true)
    }

    /// Get the default kernel for the given platform.
    func getDefaultKernel(platform: SystemPlatform) async throws -> Kernel {
        let kernelPath = kernelsRoot.appendingPathComponent("default-\(platform.architecture.rawValue)")

        guard FileManager.default.fileExists(atPath: kernelPath.path) else {
            throw ContainerizationError(
                .notFound,
                message: "Default kernel not found for \(platform.architecture.rawValue)"
            )
        }

        return Kernel(path: kernelPath, platform: platform)
    }

    /// Install a kernel binary for the given platform from a tar archive.
    ///
    /// Reading the kernel out of the archive is tens of megabytes of blocking
    /// I/O, so it runs on this actor rather than on the caller that asked
    /// for it.
    func installKernelFrom(
        tar tarFile: URL,
        kernelFilePath: String,
        platform: SystemPlatform,
        force: Bool = false
    ) async throws {
        let destination = kernelsRoot.appendingPathComponent("default-\(platform.architecture.rawValue)")

        if FileManager.default.fileExists(atPath: destination.path) {
            guard force else {
                log.info("Kernel already installed for \(platform.architecture.rawValue), skipping")
                return
            }

            try FileManager.default.removeItem(at: destination)
        }

        let kernel = try extractFile(tarFile: tarFile, at: kernelFilePath)

        try kernel.write(to: destination, options: .atomic)

        log.info("Kernel installed at \(destination.path), size: \(kernel.count) bytes")
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
