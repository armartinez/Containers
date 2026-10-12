//
//  DNSManager.swift
//  Containers
//
//  Manager for DNS resolver configuration
//  Architecture: Utility manager for DNS resolver files
//
//  Created by Axel Martinez on 2026/02/04.
//

import Foundation
import Logging
import Observation

/// Manages DNS resolver configuration for container domains.
@Observable
@MainActor
public final class NetworkManager {
    public static let resolverDirectory = URL(fileURLWithPath: "/etc/resolver", isDirectory: true)

    private static let filePrefix = "containerization."

    private let logger: Logger

    /// Public initializer - creates instance
    public init() {
        var logger = Logger(label: "app.containers.manager.network")
        logger.logLevel = .debug
        self.logger = logger
    }

    // MARK: - Public API

    public func listDomains(in directory: URL) -> [String] {
        let fileManager = FileManager.default
        let isScoped = directory.startAccessingSecurityScopedResource()

        defer {
            if isScoped {
                directory.stopAccessingSecurityScopedResource()
            }
        }

        guard
            let filenames = try? fileManager.contentsOfDirectory(atPath: directory.path)
        else {
            logger.debug("Unreadable resolver directory: \(directory.path)")

            return []
        }

        return
            filenames
            .filter { $0.hasPrefix(Self.filePrefix) }
            .compactMap { domain(inResolverNamed: $0, in: directory) }
            .sorted()
    }

    private func domain(inResolverNamed filename: String, in directory: URL) -> String? {
        let path = directory.appendingPathComponent(filename)

        guard let text = try? String(contentsOf: path, encoding: .utf8) else {
            logger.debug("Unreadable resolver file: \(filename)")

            return nil
        }

        for line in text.components(separatedBy: .newlines) {
            let fields =
                line
                .trimmingCharacters(in: .whitespaces)
                .split(whereSeparator: \.isWhitespace)

            guard fields.count == 2, fields[0] == "domain" else {
                continue
            }

            return String(fields[1])
        }

        return nil
    }

    // MARK: - Create domain

    public func createDomain(name: String) throws {
        // DNS domain creation requires root privileges.
        // This functionality is disabled in the GUI.
        // Use the CLI with sudo: sudo container system dns create <domain>
        throw DNSError.notSupported
    }

    // MARK: - Delete domain

    public func deleteDomain(name: String) throws {
        // DNS domain deletion requires root privileges.
        // This functionality is disabled in the GUI.
        // Use the CLI with sudo: sudo container system dns delete <domain>
        throw DNSError.notSupported
    }

    // MARK: - Errors

    public enum DNSError: LocalizedError {
        case invalidDomainName
        case notSupported

        public var errorDescription: String? {
            switch self {
            case .invalidDomainName:
                return "Domain name cannot be empty."
            case .notSupported:
                return """
                    DNS domain management requires administrator privileges and is not available in the GUI. 
                    You can manually create resolver files in /etc/resolver/ if needed.
                    """
            }
        }
    }
}
