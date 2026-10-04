//
//  MockContainerRuntime.swift
//  ContainerSystemTests
//
//  Mock runtime for isolated testing without real container operations.
//

import Containerization
import ContainerizationError
import ContainerizationOCI
import Foundation
import Logging

@testable import ContainerSystem

/// Mock runtime that provides isolated services for testing.
///
/// Creates real but lightweight service instances backed by temporary
/// directories.  All stores (ContentStore, ImageStore) are filesystem-only
/// and safe to use in a test host without special entitlements.
///
/// The services live here rather than in the superclass's own storage, which
/// is private; the runtime's accessors are the seam, so they are overridden
/// to hand back these instances.
@MainActor
final class MockContainerRuntime: ContainerRuntime {

    private var mockContainersService: ContainersService?
    private var mockImagesService: ImagesService?
    private var mockKernelService: KernelService?
    private var mockContentStore: ContentStore?

    init() {
        super.init(forTesting: true)
    }

    // MARK: - Service Accessors

    override func getContainersService() async throws -> ContainersService {
        guard let service = mockContainersService else {
            throw ContainerizationError(
                .internalError,
                message: "Containers service not initialized"
            )
        }

        return service
    }

    override func getImagesService() async throws -> ImagesService {
        guard let service = mockImagesService else {
            throw ContainerizationError(
                .internalError,
                message: "Images service not initialized"
            )
        }

        return service
    }

    override func getKernelService() async throws -> KernelService {
        guard let service = mockKernelService else {
            throw ContainerizationError(
                .internalError,
                message: "Kernel service not initialized"
            )
        }

        return service
    }

    override func getContentStore() throws -> ContentStore {
        guard let store = mockContentStore else {
            throw ContainerizationError(
                .internalError,
                message: "Content store not initialized"
            )
        }

        return store
    }

    // MARK: - Lifecycle

    // Override start to set up isolated services in a temp directory
    override func start(appRoot: URL) async throws {
        guard !isRunning && !isStarting else {
            return
        }

        isStarting = true
        defer { isStarting = false }

        // Create directory structure
        let fm = FileManager.default
        try fm.createDirectory(at: appRoot, withIntermediateDirectories: true)

        let imagesRoot = appRoot.appendingPathComponent("images")
        try fm.createDirectory(
            at: imagesRoot,
            withIntermediateDirectories: true
        )

        // Set appRoot so getAppRoot() works
        self.appRoot = appRoot

        // Create stores — these are filesystem-only and safe in test hosts
        let localContentStore = try LocalContentStore(
            path: imagesRoot.appendingPathComponent("content")
        )
        let imageStore = try ImageStore(
            path: imagesRoot,
            contentStore: localContentStore
        )
        let snapshotsPath = imagesRoot.appendingPathComponent("snapshots")

        let images = try ImagesService(
            contentStore: localContentStore,
            imageStore: imageStore,
            snapshotsPath: snapshotsPath,
            log: logger
        )
        self.mockImagesService = images
        self.mockContentStore = localContentStore

        // ContainersService — reads existing containers from disk (empty in tests)
        self.mockContainersService = try ContainersService(
            appRoot: appRoot,
            imagesService: images,
            log: logger
        )

        // KernelService — just creates a directory
        self.mockKernelService = try KernelService(
            log: logger,
            appRoot: appRoot
        )

        isRunning = true
        startupError = nil
    }

    // Override stop to clean up
    override func stop() async throws {
        guard isRunning && !isStopping else {
            return
        }

        isStopping = true
        defer { isStopping = false }

        mockContainersService = nil
        mockImagesService = nil
        mockKernelService = nil
        mockContentStore = nil
        isRunning = false

        // Clean up temp directory
        if let root = appRoot {
            try? FileManager.default.removeItem(at: root)
            self.appRoot = nil
        }
    }
}
