//
//  ImageManagerTests.swift
//  ContainersCoreTests
//
//  Created by Axel Martinez on 2026/02/08.
//

import Containerization
import ContainerizationOCI
import Foundation
import Testing

@testable import ContainersCore

@Suite("Image manager")
struct ImageManagerTests {

    // MARK: - Setup Helper

    @MainActor
    private func setupTestSystem() async throws -> (URL, ContainerSystem) {
        let appRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-containers-\(UUID().uuidString)")

        let containerSystem = MockContainerSystem()
        try await containerSystem.start(appRoot: appRoot)

        return (appRoot, containerSystem)
    }

    // MARK: - Infrastructure Images Tests

    @Test(
        "Images the system runs itself are hidden, whatever their version",
        arguments: [
            "ghcr.io/apple/containerization/vminit:0.28.0",
            "ghcr.io/apple/containerization/vminit:0.26.5",
            "ghcr.io/apple/containerization/vminit@sha256:0123456789abcdef",
            "ghcr.io/apple/container-builder-shim/builder:0.6.1",
        ]
    )
    func hidesInfraImages(reference: String) {
        #expect(ImageManager.isInfraImage(name: reference))
    }

    @Test(
        "Other images are listed",
        arguments: [
            "docker.io/library/alpine:latest",
            "ghcr.io/apple/containerization/other:0.28.0",
            "localhost:5000/vminit:1.0",
        ]
    )
    func listsOtherImages(reference: String) {
        #expect(!ImageManager.isInfraImage(name: reference))
    }

    // MARK: - List Images Tests

    @Test("Empty store lists no images")
    @MainActor
    func emptyStoreListsNoImages() async throws {
        let (_, containerSystem) = try await setupTestSystem()

        let imageManager = ImageManager(testSystem: containerSystem)
        let images = try await imageManager.list()

        #expect(images.isEmpty)
    }

    @Test("List fails after stop")
    @MainActor
    func listFailsAfterStop() async throws {
        let (_, containerSystem) = try await setupTestSystem()

        let imageManager = ImageManager(testSystem: containerSystem)
        try await containerSystem.stop()

        await #expect(throws: (any Error).self) {
            _ = try await imageManager.list()
        }
    }

    @Test("List hides infrastructure images")
    @MainActor
    func listHidesInfrastructureImages() async throws {
        let (_, containerSystem) = try await setupTestSystem()

        let imageManager = ImageManager(testSystem: containerSystem)
        let images = try await imageManager.list()

        // Verify no infra images
        let hasInfraImages = images.contains { image in
            image.description.reference.hasPrefix("infra:")
        }
        #expect(hasInfraImages == false)
    }

    // MARK: - Save Images Tests

    @Test("Save to directory")
    @MainActor
    func saveToDirectory() async throws {
        let (_, containerSystem) = try await setupTestSystem()

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageManagerTests")
            .appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )

        let imageManager = ImageManager(testSystem: containerSystem)
        try await imageManager.save(
            images: [],
            platform: .current,
            outputURL: tempDir.appendingPathComponent("images.tar")
        )

        // Cleanup
        try? FileManager.default.removeItem(
            at: tempDir.deletingLastPathComponent()
        )
    }

    @Test("Save empty list")
    @MainActor
    func saveEmptyList() async throws {
        let (_, containerSystem) = try await setupTestSystem()

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageManagerTests")
            .appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )

        let imageManager = ImageManager(testSystem: containerSystem)
        try await imageManager.save(
            images: [],
            platform: .current,
            outputURL: tempDir.appendingPathComponent("images.tar")
        )

        // Cleanup
        try? FileManager.default.removeItem(
            at: tempDir.deletingLastPathComponent()
        )
    }

    // MARK: - Delete Images Tests

    @Test("Delete empty list")
    @MainActor
    func deleteEmptyList() async throws {
        let (_, containerSystem) = try await setupTestSystem()

        let imageManager = ImageManager(testSystem: containerSystem)
        try await imageManager.delete(images: [])
    }
}
