//
//  ContainerService.swift
//  Containers
//
//  The containers the system keeps in its folder, and runs.
//
//  Created by Axel Martinez on 2026/11/06.
//

import Containerization
import Foundation
import Logging

/// A service that keeps the system's containers, and runs them.
protocol ContainerService: Sendable {
    func addStateChangeCallback(_ callback: @escaping @Sendable @MainActor () -> Void) async

    /// Every container, sorted by ID.
    func list() async -> [ContainerSnapshot]

    /// Runs `body` with the configuration of every container, while no other container can be created.
    func withContainerList<T: Sendable>(_ body: @Sendable @escaping ([ContainerConfiguration]) async throws -> T) async throws -> T

    func create(configuration: ContainerConfiguration, kernel: Kernel, options: ContainerCreateOptions) async throws

    func bootstrap(id: String, stdio: [FileHandle?]) async throws

    func startProcess(id: String, processID: String) async throws

    func wait(id: String) async throws -> Int32

    func stop(id: String, options: ContainerStopOptions) async throws

    func delete(id: String) async throws

    func exec(id: String, arguments: [String]) async throws -> String

    func dial(id: String, port: UInt32) async throws -> FileHandle

    func resourceUsage() async -> [ContainerResourceUsage]
}

extension ContainerService {
    /// The bundles in the containers folder, with the configuration each one stores.
    static func storedBundles(in root: URL, log: Logger) -> [(configuration: ContainerConfiguration, bundle: Bundle)] {
        guard
            let directories = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
        else {
            return []
        }

        var bundles: [(configuration: ContainerConfiguration, bundle: Bundle)] = []

        for directory in directories where directory.isDirectory {
            let bundle = Bundle(path: directory)

            do {
                bundles.append((try bundle.storedConfiguration, bundle))
            } catch {
                log.warning("Failed to load container bundle at \(directory.path): \(error)")
            }
        }

        return bundles
    }
}
