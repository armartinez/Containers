//
//  ContainerCLI.swift
//  Containers
//
//  Where Apple's container CLI keeps its data.
//
//  Created by Axel Martinez on 2026/10/25.
//

import Foundation
import Observation

/// Apple's `container` command-line tool, whose data folder the app can share.
///
/// The app never looks at the CLI's processes: in ``ContainerSystem/Mode/cliCompatibility`` it treats the folder as
/// the CLI's, and only does what can't collide with the CLI's API server. Reach it through ``ContainerSystem/cli``.
@Observable
@MainActor
public final class ContainerCLI {
    private let fetchStatus: @Sendable () async throws -> Status

    public private(set) var isStatusScriptInstalled: Bool
    public private(set) var isStatusScriptOutdated: Bool

    init() {
        self.fetchStatus = {
            guard StatusScript.isInstalled else { throw ContainerCLIError.statusScriptNotInstalled }

            return try await StatusScript.run()
        }
        self.isStatusScriptInstalled = StatusScript.isInstalled
        self.isStatusScriptOutdated = StatusScript.isOutdated
    }

    #if DEBUG
    /// Creates a CLI whose status comes from `status`, with the script installed.
    init(status: @escaping @Sendable () async throws -> Status) {
        self.fetchStatus = status
        self.isStatusScriptInstalled = true
        self.isStatusScriptOutdated = false
    }
    #endif

    // MARK: - API Server

    /// The folder the CLI's running API server uses, as the status script tells, or `nil` if it isn't running.
    public func runningAppRoot() async -> URL? {
        (try? await fetchStatus())?.appRoot
    }

    /// Whether the CLI's API server is running, as the status script tells. A script that can't tell counts
    /// as no, and the start that follows says why.
    public func isRunning() async -> Bool {
        (try? await fetchStatus())?.isRunning ?? false
    }

    // MARK: - Status Script

    public func installStatusScript(at url: URL) throws {
        // Not written atomically: the panel grants this file, not a temporary one beside it.
        try Data(StatusScript.source.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path(percentEncoded: false))

        refreshStatusScript()
    }

    private func refreshStatusScript() {
        isStatusScriptInstalled = StatusScript.isInstalled
        isStatusScriptOutdated = StatusScript.isOutdated
    }

    // MARK: - Requirements

    /// Throws unless the CLI is installed, in a version the app supports.
    public func requireInstalled() async throws {
        _ = try await supportedStatus()
    }

    /// The CLI's status, once it's known to be installed in a supported version.
    func supportedStatus() async throws -> Status {
        let status: Status

        do {
            status = try await fetchStatus()
        } catch {
            refreshStatusScript()

            throw error
        }

        guard status.isInstalled else { throw ContainerCLIError.notInstalled }
        guard let cliVersion = status.cliVersion else { throw ContainerCLIError.unsupportedVersion(nil) }

        for version in [cliVersion, status.apiServerVersion].compactMap(\.self) where !Self.supportedVersions.contains(version) {
            throw ContainerCLIError.unsupportedVersion(version)
        }

        return status
    }

    /// Throws unless `appRoot` is a CLI's folder the app can read.
    func requireReadableAppRoot(_ appRoot: URL) throws {
        guard Self.isAppRoot(appRoot) else { throw ContainerCLIError.notAppRoot }

        let isReadable = appRoot.withSecurityScopedAccess {
            (try? FileManager.default.contentsOfDirectory(atPath: appRoot.path(percentEncoded: false))) != nil
        }

        guard isReadable else { throw ContainerCLIError.noAppRootAccess }
    }
}
