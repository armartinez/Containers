//
//  LocalhostDNSHandler.swift
//  Containers
//
//  Created by Axel Martinez on 2026/10/30.
//

import ContainerizationExtras
import Foundation

/// Answers for the domains `container system dns create --localhost` points at the Mac, from their resolver files.
actor LocalhostDNSHandler: DNSHandler {
    /// The CLI's resolver files for these domains: `containerization.<domain>`, holding `options localhost:<address>`.
    static let filePrefix = "containerization."

    private let ttl: UInt32
    private var addresses: [DNSName: IPv4Address] = [:]

    init(ttl: UInt32 = 5) {
        self.ttl = ttl
    }

    /// Reads the domains from a resolver folder, replacing those read before.
    func reload(from directory: URL) {
        addresses = Self.addresses(in: directory)
    }

    func answer(query: Message) async throws -> Message? {
        guard let question = query.questions.first else {
            return nil
        }

        let name = question.name.hasSuffix(".") ? String(question.name.dropLast()) : question.name

        guard let key = try? DNSName(name), let address = addresses[key] else {
            return nil
        }

        switch question.type {
        case .host:
            return Message(
                id: query.id,
                type: .response,
                returnCode: .noError,
                questions: query.questions,
                answers: [HostRecord<IPv4Address>(name: question.name, ttl: ttl, ip: address)]
            )
        case .host6:
            return Message(id: query.id, type: .response, returnCode: .noError, questions: query.questions, answers: [])
        default:
            return Message(id: query.id, type: .response, returnCode: .notImplemented, questions: query.questions, answers: [])
        }
    }

    static func addresses(in directory: URL) -> [DNSName: IPv4Address] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var addresses: [DNSName: IPv4Address] = [:]

        for file in files where file.lastPathComponent.hasPrefix(filePrefix) {
            guard let contents = try? String(contentsOf: file, encoding: .utf8),
                let match = contents.firstMatch(of: #/options localhost:(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/#),
                let address = try? IPv4Address(String(match.1)),
                let name = try? DNSName(String(file.lastPathComponent.dropFirst(filePrefix.count)))
            else {
                continue
            }

            addresses[name] = address
        }

        return addresses
    }
}
