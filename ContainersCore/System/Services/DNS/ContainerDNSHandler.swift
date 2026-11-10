//
//  ContainerDNSHandler.swift
//  Containers
//
//  Created by Axel Martinez on 2026/10/30.
//

import ContainerizationExtras
import Foundation

/// Answers for the hostnames and aliases of running containers.
struct ContainerDNSHandler: DNSHandler {
    let containers: @Sendable () async -> [ContainerSnapshot]
    var ttl: UInt32 = 5

    func answer(query: Message) async throws -> Message? {
        guard let question = query.questions.first else {
            return nil
        }

        guard question.type == .host || question.type == .host6 else {
            return Message(id: query.id, type: .response, returnCode: .notImplemented, questions: query.questions, answers: [])
        }

        guard let attachment = Self.attachment(for: question.name, in: await containers()) else {
            return nil
        }

        let record: ResourceRecord?

        if question.type == .host {
            record = HostRecord<IPv4Address>(name: question.name, ttl: ttl, ip: attachment.ipv4Address.address)
        } else {
            // A name with no IPv6 address answers with no records, not NXDOMAIN, which musl takes to mean the name doesn't exist.
            record = attachment.ipv6Address.map { HostRecord<IPv6Address>(name: question.name, ttl: ttl, ip: $0.address) }
        }

        return Message(
            id: query.id,
            type: .response,
            returnCode: .noError,
            questions: query.questions,
            answers: record.map { [$0] } ?? []
        )
    }

    /// The attachment a name resolves to: a hostname first, then an exact alias, then the subtree alias with the
    /// longest base.
    static func attachment(for name: String, in snapshots: [ContainerSnapshot]) -> Attachment? {
        let name = canonical(name)
        let attachments = snapshots.filter { $0.status == .running }.flatMap { snapshot in
            snapshot.networks.enumerated().map { index, attachment in
                let aliases = snapshot.configuration.networks.indices.contains(index) ? snapshot.configuration.networks[index].options.aliases : []

                return (attachment: attachment, aliases: aliases.map(canonical))
            }
        }

        if let match = attachments.first(where: { canonical($0.attachment.hostname) == name }) {
            return match.attachment
        }

        if let match = attachments.first(where: { $0.aliases.contains(name) }) {
            return match.attachment
        }

        guard let dnsName = try? DNSName(name) else { return nil }

        for base in DNSMatchRule.subtreeBases(of: dnsName) {
            if let match = attachments.first(where: { $0.aliases.contains("." + base.pqdn) }) {
                return match.attachment
            }
        }

        return nil
    }

    /// A name as compared: lowercased, without a trailing dot.
    private static func canonical(_ name: String) -> String {
        (name.hasSuffix(".") ? String(name.dropLast()) : name).lowercased()
    }
}
