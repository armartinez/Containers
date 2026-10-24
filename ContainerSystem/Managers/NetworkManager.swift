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

/// A manager that reads the DNS domains configured for containers on the Mac.
///
/// macOS keeps a resolver file for each domain in ``resolverDirectory``. Changing those files needs
/// administrator privileges, so this manager can list domains but not create or delete them.
@Observable
@MainActor
public final class NetworkManager {
    /// The folder where macOS keeps a resolver file for each DNS domain.
    public static let resolverDirectory = URL(fileURLWithPath: "/etc/resolver", isDirectory: true)

    private static let filePrefix = "containerization."

    private let logger: Logger

    /// Creates a manager for the shared container system.
    public init() {
        var logger = Logger(label: "app.containers.manager.network")
        logger.logLevel = .debug
        self.logger = logger
    }

    // MARK: - Public API

    /// Returns the DNS domains that resolver files in a folder configure for containers, sorted by name.
    ///
    /// Only the resolver files the container tools create are read, and a file without a `domain` entry
    /// is skipped.
    ///
    /// - Parameter directory: The folder to read, usually ``resolverDirectory``.
    /// - Returns: The domains, or an empty array if the folder can't be read.
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

    /// Creates a DNS domain for containers.
    ///
    /// Creating a resolver file needs administrator privileges, which the app doesn't have, so this method
    /// always throws ``DNSError/notSupported``.
    ///
    /// - Parameter name: The domain to create.
    /// - Throws: ``DNSError/notSupported``, always.
    public func createDomain(name: String) throws {
        // DNS domain creation requires root privileges.
        // This functionality is disabled in the GUI.
        // Use the CLI with sudo: sudo container system dns create <domain>
        throw DNSError.notSupported
    }

    // MARK: - Delete domain

    /// Deletes a DNS domain for containers.
    ///
    /// Deleting a resolver file needs administrator privileges, which the app doesn't have, so this method
    /// always throws ``DNSError/notSupported``.
    ///
    /// - Parameter name: The domain to delete.
    /// - Throws: ``DNSError/notSupported``, always.
    public func deleteDomain(name: String) throws {
        // DNS domain deletion requires root privileges.
        // This functionality is disabled in the GUI.
        // Use the CLI with sudo: sudo container system dns delete <domain>
        throw DNSError.notSupported
    }

    // MARK: - Errors

    /// Errors that DNS domain operations throw.
    public enum DNSError: LocalizedError {
        /// The domain name isn't valid.
        case invalidDomainName
        /// The app can't create or delete DNS domains.
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
