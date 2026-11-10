//
//  ContainerCLI+Status.swift
//  Containers
//
//  Created by Axel Martinez on 2026/11/05.
//

import Foundation

extension ContainerCLI {
    struct Status: Sendable {
        var isInstalled: Bool
        var isRunning: Bool
        var appRoot: URL?
        var cliVersion: String?
        var apiServerVersion: String?
    }

    struct StatusError: LocalizedError {
        var output: String

        var errorDescription: String? {
            "The container CLI’s status couldn’t be read."
        }

        var failureReason: String? {
            output.isEmpty ? nil : output
        }
    }
}

extension ContainerCLI.Status: Decodable {
    private enum CodingKeys: String, CodingKey {
        case versions
        case status
    }

    private struct Version: Decodable {
        var appName: String
        var version: String
    }

    private struct SystemStatus: Decodable {
        struct Paths: Decodable {
            var appRoot: String?
        }

        var status: String
        var paths: Paths?
    }

    /// Reads the status script's output.
    init(output data: Data) throws {
        do {
            self = try JSONDecoder().decode(Self.self, from: data)
        } catch {
            throw ContainerCLI.StatusError(output: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let versions = try container.decode([Version].self, forKey: .versions)
        let status = try container.decode(SystemStatus.self, forKey: .status)

        // A "not running" API server is still registered, and launched on demand.
        let isInstalled = status.status != "notInstalled"
        let isRunning = isInstalled && status.status != "unregistered"

        self.init(
            isInstalled: isInstalled,
            isRunning: isRunning,
            appRoot: isRunning ? status.paths?.appRoot.map { URL(filePath: $0, directoryHint: .isDirectory) } : nil,
            cliVersion: versions.first { $0.appName == "container" }?.version,
            apiServerVersion: versions.first { $0.appName == "container-apiserver" }?.version
        )
    }
}
