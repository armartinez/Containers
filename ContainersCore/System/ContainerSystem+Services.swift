//
//  ContainerSystem+Services.swift
//  Containers
//
//  The services the container system runs, made for its mode.
//
//  Created by Axel Martinez on 2026/11/08.
//

import Containerization
import ContainerizationOCI
import Foundation

extension ContainerSystem {
    /// The services the system runs.
    struct Services {
        let containerService: any ContainerService
        let imageService: any ImageService
        let networkService: any NetworkService
        let volumeService: any VolumeService
        let kernelService: KernelService
        /// Reports are the app's own, kept out of the CLI's folder, so a read-only system has none.
        let reportService: ReportService?
    }

    /// Makes the services for the system's mode: beside the CLI's running API server, the variants that
    /// only read the folder.
    func makeServices(appRoot: URL, readOnly: Bool) throws -> Services {
        logger.info("Initializing services...")

        // The image store sits at the root, so the CLI can share it.
        let contentStore = try LocalContentStore(
            path: appRoot.appendingPathComponent("content")
        )
        let imageStore = try ImageStore(
            path: appRoot,
            contentStore: contentStore
        )
        let snapshotsPath = appRoot.appendingPathComponent("snapshots")
        let kernelService = try KernelService(log: logger, appRoot: appRoot)

        guard !readOnly else {
            return Services(
                containerService: ReadOnlyContainerService(appRoot: appRoot, log: logger),
                imageService: ReadOnlyImageService(imageStore: imageStore, contentStore: contentStore, snapshotsPath: snapshotsPath),
                networkService: ReadOnlyNetworkService(appRoot: appRoot, log: logger),
                volumeService: ReadOnlyVolumeService(appRoot: appRoot, log: logger),
                kernelService: kernelService,
                reportService: nil
            )
        }

        let images = try DefaultImageService(
            contentStore: contentStore,
            imageStore: imageStore,
            snapshotsPath: snapshotsPath,
            log: logger
        )
        let networks = DefaultNetworkService(appRoot: appRoot, log: logger)
        let volumes = DefaultVolumeService(appRoot: appRoot, log: logger)
        let containers = try DefaultContainerService(
            appRoot: appRoot,
            imageService: images,
            networkService: networks,
            log: logger
        )

        return Services(
            containerService: containers,
            imageService: images,
            networkService: networks,
            volumeService: volumes,
            kernelService: kernelService,
            reportService: try ReportService(appRoot: appRoot, log: logger)
        )
    }

    /// Keeps the system's observable state in step with the services.
    func observe(_ services: Services) async {
        await services.containerService.addStateChangeCallback { @MainActor [weak self] in
            self?.lastContainerStateChange = Date()
        }

        await services.reportService?.addChangeCallback { @MainActor [weak self] reports in
            self?.reports = reports
        }
    }

    func createDataDirectories(appRoot: URL) throws {
        logger.info("Creating data directories...")

        // The services create the folders they keep inside it.
        try FileManager.default.createDirectory(
            at: appRoot,
            withIntermediateDirectories: true
        )
    }

    /// Picks up the containers the CLI made or removed, while the system is read-only.
    func reloadSharedContainers() async {
        guard let service = try? containerService as? ReadOnlyContainerService else { return }
        await service.reload()
    }
}
