//
//  DNSServiceTests.swift
//  ContainersCoreTests
//
//  Created by Axel Martinez on 2026/10/30.
//

import Containerization
import ContainerizationExtras
import ContainerizationOCI
import Darwin
import Foundation
import Testing

@testable import ContainersCore

@Suite("DNS service")
struct DNSServiceTests {
    private func snapshot(id: String, hostname: String, address: String, aliases: [String] = [], status: ContainerStatus = .running) throws
        -> ContainerSnapshot
    {
        var configuration = ContainerConfiguration(
            id: id,
            image: ImageDescription(
                reference: "docker.io/library/alpine:latest",
                descriptor: Descriptor(mediaType: "", digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", size: 0)
            ),
            process: ProcessConfiguration(executable: "/bin/sh")
        )
        configuration.networks = [AttachmentConfiguration(network: "default", options: AttachmentOptions(hostname: hostname, aliases: aliases))]

        let attachment = Attachment(
            network: "default",
            hostname: hostname,
            ipv4Address: try CIDRv4("\(address)/24"),
            ipv4Gateway: try IPv4Address("192.168.64.1")
        )

        return ContainerSnapshot(configuration: configuration, status: status, networks: [attachment])
    }

    @Test("Resolves a running container's hostname, then its exact aliases, then the longest subtree alias")
    func matchesHostnamesAndAliases() throws {
        let snapshots = [
            try snapshot(id: "web", hostname: "web.test.", address: "192.168.64.2", aliases: ["www.test", ".apps.test"]),
            try snapshot(id: "api", hostname: "api.test.", address: "192.168.64.3", aliases: [".api.apps.test"]),
            try snapshot(id: "old", hostname: "old.test.", address: "192.168.64.4", status: .stopped),
        ]

        #expect(ContainerDNSHandler.attachment(for: "WEB.test.", in: snapshots)?.hostname == "web.test.")
        #expect(ContainerDNSHandler.attachment(for: "www.test", in: snapshots)?.hostname == "web.test.")
        #expect(ContainerDNSHandler.attachment(for: "blog.apps.test.", in: snapshots)?.hostname == "web.test.")
        #expect(ContainerDNSHandler.attachment(for: "v1.api.apps.test.", in: snapshots)?.hostname == "api.test.")
        #expect(ContainerDNSHandler.attachment(for: "old.test.", in: snapshots) == nil)
        #expect(ContainerDNSHandler.attachment(for: "other.test.", in: snapshots) == nil)
    }

    @Test("Reads the localhost domains from the CLI's resolver files")
    func readsLocalhostDomains() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        try directory.write("domain host.internal\nsearch host.internal\nnameserver 127.0.0.1\nport 1053\noptions localhost:203.0.113.10\n", to: "containerization.host.internal")
        try directory.write("domain test\nnameserver 127.0.0.1\nport 2053\n", to: "containerization.test")
        try directory.write("nameserver 10.0.0.1\n", to: "corp.example")

        let addresses = LocalhostDNSHandler.addresses(in: directory.url)

        #expect(addresses.count == 1)
        #expect(addresses[try DNSName("host.internal")] == (try IPv4Address("203.0.113.10")))
    }

    @Test("Answers a query over UDP on the loopback address, from inside the app's sandbox")
    func answersOverUDP() async throws {
        let snapshots = [try snapshot(id: "web", hostname: "web.test.", address: "192.168.64.2")]
        let handler = ContainerDNSHandler { snapshots }
        let server = DNSServer(handler: StandardQueryValidator(handler: CompositeResolver(handlers: [handler, NxDomainResolver()])))
        let port = Int.random(in: 40_000..<50_000)
        let serving = Task { try await server.run(host: "127.0.0.1", port: port) }
        defer { serving.cancel() }

        // Lets the server bind before the query is sent.
        try await Task.sleep(for: .milliseconds(200))

        let query = Message(id: 42, type: .query, questions: [Question(name: "web.test.", type: .host)])
        let response = try Self.exchange(try query.serialize(), port: port)
        let reply = try Message(deserialize: response)

        #expect(reply.id == 42)
        #expect(reply.returnCode == .noError)
        // The decoder reads only questions, so the answer is checked in the bytes: one answer, ending in its IPv4 address.
        #expect(UInt16(response[6]) << 8 | UInt16(response[7]) == 1)
        #expect(Array(response.suffix(4)) == [192, 168, 64, 2])
    }

    /// Sends a datagram to the loopback address and waits up to two seconds for the reply.
    private static func exchange(_ request: Data, port: Int) throws -> Data {
        let socket = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        try #require(socket >= 0)
        defer { close(socket) }

        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let sent = request.withUnsafeBytes { bytes in
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(socket, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        try #require(sent == request.count)

        var buffer = [UInt8](repeating: 0, count: 512)
        let received = recv(socket, &buffer, buffer.count, 0)
        try #require(received > 0)

        return Data(buffer.prefix(received))
    }
}
