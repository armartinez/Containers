//
//  NetworksTests.swift
//  ContainersCoreTests
//
//  Created by Axel Martinez on 2026/10/31.
//

import Containerization
import ContainerizationError
import ContainerizationExtras
import ContainerizationOCI
import Foundation
import Logging
import Testing

@testable import ContainersCore

@Suite("Networks")
struct NetworksTests {
    /// What CLI 1.6.1 writes for its built-in network.
    private static let cliDefaultNetwork = """
        {"plugin":"container-network-vmnet","mode":"nat","labels":{"com.apple.container.resource.role":"builtin"},\
        "name":"default","creationDate":815058191.631105,"options":{}}
        """

    private func makeService(in directory: TemporaryDirectory) -> DefaultNetworkService {
        DefaultNetworkService(appRoot: directory.url, log: Logger(label: "tests.networks"))
    }

    @Test("Reads the CLI's built-in network, and writes it back with the same keys")
    func readsAndWritesCLINetwork() throws {
        let network = try JSONDecoder().decode(NetworkConfiguration.self, from: Data(Self.cliDefaultNetwork.utf8))

        #expect(network.name == "default")
        #expect(network.mode == .nat)
        #expect(network.isBuiltin)
        #expect(network.ipv4Subnet == nil)

        let encoded = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(network)) as? [String: Any]
        let original = try JSONSerialization.jsonObject(with: Data(Self.cliDefaultNetwork.utf8)) as? [String: Any]

        #expect(encoded.map { Set($0.keys) } == original.map { Set($0.keys) })
    }

    @Test("Reads a network the CLI wrote before 1.0, with a subnet and no plugin")
    func readsLegacyNetwork() throws {
        let legacy = #"{"id":"backend","mode":"hostOnly","subnet":"192.168.100.0/24"}"#
        let network = try JSONDecoder().decode(NetworkConfiguration.self, from: Data(legacy.utf8))

        #expect(network.name == "backend")
        #expect(network.mode == .hostOnly)
        #expect(network.ipv4Subnet?.description == "192.168.100.0/24")
        #expect(network.plugin == "container-network-vmnet")
    }

    @Test("Makes the built-in network when the folder has none, but not in the CLI's running folder")
    func makesBuiltinNetwork() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let service = makeService(in: directory)

        #expect(try await service.list().map(\.name) == ["default"])
        #expect(FileManager.default.fileExists(atPath: directory.appending("networks/default/entity.json").path))

        let readOnlyFolder = try TemporaryDirectory()
        defer { readOnlyFolder.remove() }

        let readOnlyService = ReadOnlyNetworkService(appRoot: readOnlyFolder.url, log: Logger(label: "tests.networks"))

        #expect(try await readOnlyService.list().map(\.name) == ["default"])
        #expect(!FileManager.default.fileExists(atPath: readOnlyFolder.appending("networks/default/entity.json").path))
    }

    @Test("Refuses a taken name, an overlapping subnet, an invalid name, and deleting the built-in network or one in use")
    func refusesInvalidNetworks() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let service = makeService(in: directory)

        try await service.create(try NetworkConfiguration(name: "backend", ipv4Subnet: try CIDRv4("192.168.100.0/24")))

        #expect(try await service.list().map(\.name) == ["backend", "default"])

        await #expect(throws: ContainerizationError.self) {
            try await service.create(try NetworkConfiguration(name: "backend"))
        }
        await #expect(throws: ContainerizationError.self) {
            try await service.create(try NetworkConfiguration(name: "other", ipv4Subnet: try CIDRv4("192.168.100.128/25")))
        }
        #expect(throws: ContainerizationError.self) {
            try NetworkConfiguration(name: "Not Valid")
        }
        await #expect(throws: ContainerizationError.self) {
            try await service.delete(named: "default", inUseBy: [])
        }
        await #expect(throws: ContainerizationError.self) {
            try await service.delete(named: "backend", inUseBy: ["web"])
        }

        try await service.delete(named: "backend", inUseBy: [])

        #expect(try await service.list().map(\.name) == ["default"])
    }
}
