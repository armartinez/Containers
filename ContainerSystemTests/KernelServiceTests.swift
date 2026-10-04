//
//  KernelServiceTests.swift
//  ContainerSystemTests
//
//  Installing a kernel out of the archive the app downloads.
//

import Containerization
import ContainerizationArchive
import Foundation
import Logging
import Testing

@testable import ContainerSystem

@Suite("Kernel service")
struct KernelServiceTests {

    private func makeService(in directory: TemporaryDirectory) throws
        -> KernelService
    {
        try KernelService(
            log: Logger(label: "tests.kernel"),
            appRoot: directory.url
        )
    }

    /// Writes a tar holding `files`, plus `symlinks` as real symlink entries.
    private func makeArchive(
        at url: URL,
        files: [String: String],
        symlinks: [String: String] = [:]
    ) throws {
        let writer = try ArchiveWriter(format: .pax, filter: .none, file: url)

        for (path, contents) in files.sorted(by: { $0.key < $1.key }) {
            let data = Data(contents.utf8)
            let entry = WriteEntry()

            entry.path = path
            entry.fileType = .regular
            entry.permissions = 0o644
            entry.size = Int64(data.count)

            try writer.writeEntry(entry: entry, data: data)
        }

        for (path, target) in symlinks.sorted(by: { $0.key < $1.key }) {
            let entry = WriteEntry()

            entry.path = path
            entry.fileType = .symbolicLink
            entry.symlinkTarget = target
            entry.permissions = 0o777
            entry.size = 0

            try writer.writeEntry(entry: entry, data: Data())
        }

        try writer.finishEncoding()
    }

    private func installedKernel(
        from service: KernelService
    ) async throws -> Data {
        let kernel = try await service.getDefaultKernel(platform: .current)

        return try Data(contentsOf: kernel.path)
    }

    @Test("Install named kernel")
    func installsNamedKernel() async throws {
        let directory = try TemporaryDirectory("kernel-install")
        defer { directory.remove() }

        let tar = directory.appending("kernel.tar")
        try makeArchive(
            at: tar,
            files: ["boot/vmlinux": "real kernel", "boot/README": "ignore me"]
        )

        let service = try makeService(in: directory)
        try await service.installKernelFrom(
            tar: tar,
            kernelFilePath: "boot/vmlinux",
            platform: .current
        )

        #expect(try await installedKernel(from: service) == Data("real kernel".utf8))
    }

    @Test("Install follows symlink")
    func followsSymlink() async throws {
        let directory = try TemporaryDirectory("kernel-symlink")
        defer { directory.remove() }

        // What the Apple kernel archives actually ship: a stable name that
        // points at the versioned binary sitting beside it.
        let tar = directory.appending("kernel.tar")
        try makeArchive(
            at: tar,
            files: ["boot/vmlinux-6.12": "versioned kernel"],
            symlinks: ["boot/vmlinux": "vmlinux-6.12"]
        )

        let service = try makeService(in: directory)
        try await service.installKernelFrom(
            tar: tar,
            kernelFilePath: "boot/vmlinux",
            platform: .current
        )

        // The link's own (empty) payload must not be what lands on disk.
        #expect(
            try await installedKernel(from: service)
                == Data("versioned kernel".utf8)
        )
    }

    @Test("Keep existing kernel")
    func keepsExistingKernel() async throws {
        let directory = try TemporaryDirectory("kernel-keep")
        defer { directory.remove() }

        let service = try makeService(in: directory)

        let first = directory.appending("first.tar")
        try makeArchive(at: first, files: ["vmlinux": "first kernel"])
        try await service.installKernelFrom(
            tar: first,
            kernelFilePath: "vmlinux",
            platform: .current
        )

        let second = directory.appending("second.tar")
        try makeArchive(at: second, files: ["vmlinux": "second kernel"])
        try await service.installKernelFrom(
            tar: second,
            kernelFilePath: "vmlinux",
            platform: .current,
            force: false
        )

        #expect(try await installedKernel(from: service) == Data("first kernel".utf8))
    }

    @Test("Force replaces kernel")
    func forceReplacesKernel() async throws {
        let directory = try TemporaryDirectory("kernel-force")
        defer { directory.remove() }

        let service = try makeService(in: directory)

        let first = directory.appending("first.tar")
        try makeArchive(at: first, files: ["vmlinux": "first kernel"])
        try await service.installKernelFrom(
            tar: first,
            kernelFilePath: "vmlinux",
            platform: .current
        )

        let second = directory.appending("second.tar")
        try makeArchive(at: second, files: ["vmlinux": "second kernel"])
        try await service.installKernelFrom(
            tar: second,
            kernelFilePath: "vmlinux",
            platform: .current,
            force: true
        )

        #expect(try await installedKernel(from: service) == Data("second kernel".utf8))
    }

    @Test("Missing kernel fails")
    func missingKernelFails() async throws {
        let directory = try TemporaryDirectory("kernel-missing")
        defer { directory.remove() }

        let service = try makeService(in: directory)

        await #expect(throws: (any Error).self) {
            _ = try await service.getDefaultKernel(platform: .current)
        }
    }

    @Test("Missing archive member fails")
    func missingArchiveMemberFails() async throws {
        let directory = try TemporaryDirectory("kernel-bad-path")
        defer { directory.remove() }

        let tar = directory.appending("kernel.tar")
        try makeArchive(at: tar, files: ["boot/vmlinux": "real kernel"])

        let service = try makeService(in: directory)

        await #expect(throws: (any Error).self) {
            try await service.installKernelFrom(
                tar: tar,
                kernelFilePath: "boot/does-not-exist",
                platform: .current
            )
        }

        // A failed install must not leave a half-written kernel behind.
        await #expect(throws: (any Error).self) {
            _ = try await service.getDefaultKernel(platform: .current)
        }
    }
}
