//
//  NetworkManagerTests.swift
//  ContainerSystemTests
//
//  The DNS domains read out of the resolver files the CLI writes.
//

import Foundation
import Testing

@testable import ContainerSystem

@Suite("Network manager")
@MainActor
struct NetworkManagerTests {

    /// A resolver directory of its own, since the real one cannot be written
    /// to without being root.
    private func resolverDirectory(
        _ files: [String: String]
    ) throws -> URL {
        let directory = URL.temporaryDirectory
            .appendingPathComponent("resolver-\(UUID().uuidString)")

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        for (name, contents) in files {
            try contents.write(
                to: directory.appendingPathComponent(name),
                atomically: true,
                encoding: .utf8
            )
        }

        return directory
    }

    /// What `container system dns create test` leaves behind.
    private let cliResolver = """
        domain test
        search test
        nameserver 127.0.0.1
        port 2053

        """

    @Test("Domain is read from contents")
    func readsDomainFromContents() throws {
        let directory = try resolverDirectory([
            // The file is for `test`, whatever its own name says.
            "containerization.renamed": cliResolver
        ])

        let manager = NetworkManager()

        #expect(manager.listDomains(in: directory) == ["test"])
    }

    @Test("Other resolvers are ignored")
    func ignoresForeignResolvers() throws {
        let directory = try resolverDirectory([
            "containerization.test": cliResolver,
            "example.com": "domain example.com\nnameserver 8.8.8.8\n",
        ])

        let manager = NetworkManager()

        #expect(manager.listDomains(in: directory) == ["test"])
    }

    /// The CLI passes over a file it cannot read a domain out of, so a file
    /// written by hand without that line is not a domain either.
    @Test("Resolver without domain is skipped")
    func skipsResolverWithoutDomain() throws {
        let directory = try resolverDirectory([
            "containerization.test": "nameserver 127.0.0.1\nport 2053\n"
        ])

        let manager = NetworkManager()

        #expect(manager.listDomains(in: directory).isEmpty)
    }

    @Test("Domains are sorted")
    func sortsDomains() throws {
        let directory = try resolverDirectory([
            "containerization.zulu": "domain zulu\n",
            "containerization.alpha": "domain alpha\n",
            "containerization.mike": "domain mike\n",
        ])

        let manager = NetworkManager()

        #expect(manager.listDomains(in: directory) == ["alpha", "mike", "zulu"])
    }

    @Test("Localhost resolver is read")
    func readsLocalhostResolver() throws {
        // What `--localhost` adds: a redirected address, and 1053 for a port.
        let directory = try resolverDirectory([
            "containerization.local": """
                domain local
                search local
                nameserver 127.0.0.1
                port 1053
                options localhost:192.168.64.1
            """
        ])

        let manager = NetworkManager()

        #expect(manager.listDomains(in: directory) == ["local"])
    }

    @Test("Missing directory yields no domains")
    func toleratesMissingDirectory() {
        let absent = URL.temporaryDirectory
            .appendingPathComponent("absent-\(UUID().uuidString)")

        #expect(NetworkManager().listDomains(in: absent).isEmpty)
    }
}
