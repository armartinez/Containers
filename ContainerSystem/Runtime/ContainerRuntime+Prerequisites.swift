//
//  ContainerRuntime+Prerequisites.swift
//  Containers
//
//  Prerequisites installation extension for ContainerRuntime.
//  Handles installation of init filesystem and default kernel.
//
//  Created by Axel Martinez on 2026/02/08.
//

import Containerization
import ContainerizationError
import ContainerizationOCI
import Foundation

extension ContainerRuntime {
    func installPrerequisites() async throws {
        let initExists = await initImageExists()
        let kernelExistsResult = await kernelExists()

        guard !initExists || !kernelExistsResult else { return }

        // Only what is missing is counted, so the bar measures what will actually be done.
        let progress = Progress.discreteProgress(
            totalUnitCount: (initExists ? 0 : 2) + (kernelExistsResult ? 0 : 2)
        )

        setupProgress = progress

        defer {
            setupProgress = nil
        }

        if !initExists {
            try Task.checkCancellation()
            logger.info("Installing base container filesystem...")
            try await progress.performStep(pendingUnitCount: 2) { step in
                try await installInitialFilesystem(progress: step)
            }
        }

        if !kernelExistsResult {
            try Task.checkCancellation()
            logger.info("Installing default kernel...")
            try await progress.performStep(pendingUnitCount: 2) { step in
                try await installDefaultKernel(progress: step)
            }
            logger.info("Kernel installed")
        }
    }

    // MARK: - Private Helpers

    private func installInitialFilesystem(progress: Progress) async throws {
        let initFsRef = DefaultsStore.get(key: .defaultInitImage)

        let service = try await getImagesService()

        progress.totalUnitCount = 2

        let imageDescription = try await progress.performStep(
            "Fetching init image"
        ) { step in
            try await service.pull(
                reference: initFsRef,
                platform: .current,
                insecure: false,
                progressUpdate: step.updateHandler()
            )
        }

        try Task.checkCancellation()

        try await progress.performStep("Unpacking init image") { step in
            try await service.unpack(
                description: imageDescription,
                platform: .current,
                progressUpdate: step.updateHandler()
            )
        }
    }

    private func installDefaultKernel(progress: Progress) async throws {
        // Get kernel URL and binary path from DefaultsStore (same as Apple Container CLI)
        let defaultKernelURL = DefaultsStore.get(key: .defaultKernelURL)
        let defaultKernelBinaryPath = DefaultsStore.get(
            key: .defaultKernelBinaryPath
        )

        logger.info(
            "Starting kernel installation from: \(defaultKernelURL)"
        )

        logger.info(
            "Kernel binary path in archive: \(defaultKernelBinaryPath)"
        )

        guard let sourceURL = URL(string: defaultKernelURL) else {
            throw ContainerizationError(
                .invalidArgument,
                message: "Invalid kernel URL: \(defaultKernelURL)"
            )
        }

        // Create temp directory for download and extraction
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Download the kernel tar file
        let tarFile = tempDir.appendingPathComponent(
            sourceURL.lastPathComponent
        )

        logger.info("Downloading from: \(sourceURL) to: \(tarFile.path)")

        progress.totalUnitCount = 2

        let response = try await progress.performStep("Downloading kernel") { step in
            try await FileDownloader(destination: tarFile, progress: step).download(from: sourceURL)
        }

        if let httpResponse = response as? HTTPURLResponse {
            logger.info("Download response status: \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200 else {
                throw ContainerizationError(
                    .internalError,
                    message:
                        "Failed to download kernel: HTTP \(httpResponse.statusCode)"
                )
            }
        }

        logger.info("Downloaded to: \(tarFile.path)")

        try Task.checkCancellation()

        // Unpacking happens on the kernel service's actor, off the main thread
        try await progress.performStep("Unpacking kernel") { _ in
            let service = try await getKernelService()

            try await service.installKernelFrom(
                tar: tarFile,
                kernelFilePath: defaultKernelBinaryPath,
                platform: .current,
                force: true
            )
        }

        logger.info("Kernel installed successfully")
    }

    private func initImageExists() async -> Bool {
        guard let service = try? await getImagesService() else {
            return false
        }

        do {
            let images = try await service.list()
            let initFsRef = DefaultsStore.get(key: .defaultInitImage)

            return images.contains { $0.reference == initFsRef }
        } catch {
            return false
        }
    }

    private func kernelExists() async -> Bool {
        guard let service = try? await getKernelService() else {
            return false
        }

        do {
            _ = try await service.getDefaultKernel(platform: .current)

            return true
        } catch {
            logger.warning("Failed to check kernel: \(error)")

            return false
        }
    }
}
