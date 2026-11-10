//
//  MockContainerSystem.swift
//  ContainersCoreTests
//
//  A container system for isolated testing without real container operations.
//

import Containerization
import ContainerizationError
import ContainerizationOCI
import Foundation
import Logging

@testable import ContainersCore

/// A container system that provides isolated services for testing.
///
/// Creates real but lightweight service instances backed by temporary
/// directories.  All stores (ContentStore, ImageStore) are filesystem-only
/// and safe to use in a test host without special entitlements.
///
/// The services live here rather than in the superclass's own storage, which
/// is private; its `…Service` properties and `launch(appRoot:readOnly:installingKernel:)`/`shutdown()` are the seam, so they
/// are overridden to hand back these instances.
@MainActor
final class MockContainerSystem: ContainerSystem {

    /// Off for a test that starts again over the same folder, which the real system leaves in place.
    var removesAppRootOnStop = true

    private var mockContainerService: (any ContainerService)?
    private var mockImageService: (any ImageService)?
    private var mockNetworkService: (any NetworkService)?
    private var mockVolumeService: (any VolumeService)?
    private var mockKernelService: KernelService?
    private var mockReportService: ReportService?

    init(cliStatus: (@Sendable () async throws -> ContainerCLI.Status)? = nil) {
        if let cliStatus {
            super.init(cliStatus: cliStatus)
        } else {
            super.init()
        }
    }

    // MARK: - Service Accessors

    override var containerService: any ContainerService {
        get throws { try running(mockContainerService) }
    }

    override var imageService: any ImageService {
        get throws { try running(mockImageService) }
    }

    override var networkService: any NetworkService {
        get throws { try running(mockNetworkService) }
    }

    override var volumeService: any VolumeService {
        get throws { try running(mockVolumeService) }
    }

    override var kernelService: KernelService {
        get throws { try running(mockKernelService) }
    }

    override var reportService: ReportService {
        get throws { try running(mockReportService) }
    }

    private func running<Value>(_ value: Value?) throws -> Value {
        guard let value else {
            throw ContainerizationError(.internalError, message: "Container system not running")
        }

        return value
    }

    // MARK: - Lifecycle

    // Sets up isolated services in a temporary folder.
    override func launch(appRoot: URL, readOnly: Bool, installingKernel: Bool) async throws {
        if status == .running || status == .readOnly {
            return
        }

        status = .starting

        defer {
            if status == .starting {
                settleStopped()
            }
        }

        // Create directory structure
        let fm = FileManager.default
        try fm.createDirectory(at: appRoot, withIntermediateDirectories: true)

        let imagesRoot = appRoot.appendingPathComponent("images")
        try fm.createDirectory(
            at: imagesRoot,
            withIntermediateDirectories: true
        )

        let reports = try ReportService(appRoot: appRoot, log: logger)

        await reports.addChangeCallback { @MainActor [weak self] reports in
            self?.reports = reports
        }

        // Create stores — these are filesystem-only and safe in test hosts
        let localContentStore = try LocalContentStore(
            path: imagesRoot.appendingPathComponent("content")
        )
        let imageStore = try ImageStore(
            path: imagesRoot,
            contentStore: localContentStore
        )
        let snapshotsPath = imagesRoot.appendingPathComponent("snapshots")

        let images = try DefaultImageService(
            contentStore: localContentStore,
            imageStore: imageStore,
            snapshotsPath: snapshotsPath,
            log: logger
        )
        let networks = DefaultNetworkService(appRoot: appRoot, log: logger)
        let volumes = DefaultVolumeService(appRoot: appRoot, log: logger)

        // KernelService — just creates a directory
        let kernel = try KernelService(
            log: logger,
            appRoot: appRoot
        )

        if readOnly {
            mockContainerService = ReadOnlyContainerService(appRoot: appRoot, log: logger)
            mockImageService = ReadOnlyImageService(imageStore: imageStore, contentStore: localContentStore, snapshotsPath: snapshotsPath)
            mockNetworkService = ReadOnlyNetworkService(appRoot: appRoot, log: logger)
            mockVolumeService = ReadOnlyVolumeService(appRoot: appRoot, log: logger)
        } else {
            // Reads existing containers from disk (empty in tests)
            mockContainerService = try DefaultContainerService(
                appRoot: appRoot,
                imageService: images,
                networkService: networks,
                log: logger
            )
            mockImageService = images
            mockNetworkService = networks
            mockVolumeService = volumes
        }

        mockKernelService = kernel
        mockReportService = reports
        self.appRoot = appRoot
        status = readOnly ? .readOnly : .running
        startupError = nil
    }

    override func shutdown() async throws {
        guard status == .running || status == .readOnly else {
            return
        }

        status = .stopping

        let appRoot = self.appRoot

        mockContainerService = nil
        mockImageService = nil
        mockNetworkService = nil
        mockVolumeService = nil
        mockKernelService = nil
        mockReportService = nil
        self.appRoot = nil
        settleStopped()

        // Clean up temp directory
        if let appRoot, removesAppRootOnStop {
            try? FileManager.default.removeItem(at: appRoot)
        }
    }
}
