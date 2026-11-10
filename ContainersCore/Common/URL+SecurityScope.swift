//
//  URL+SecurityScope.swift
//  Containers
//
//  Created by Axel Martinez on 2026/11/05.
//

import Foundation

extension URL {
    /// Runs `body` with access to the folder or file the user granted, which the sandbox only allows
    /// for a URL from a panel or a security-scoped bookmark.
    func withSecurityScopedAccess<Result>(_ body: () throws -> Result) rethrows -> Result {
        let didAccess = startAccessingSecurityScopedResource()

        defer {
            if didAccess {
                stopAccessingSecurityScopedResource()
            }
        }

        return try body()
    }

    func withSecurityScopedAccess<Result>(
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> Result
    ) async rethrows -> Result {
        let didAccess = startAccessingSecurityScopedResource()

        defer {
            if didAccess {
                stopAccessingSecurityScopedResource()
            }
        }

        return try await body()
    }
}
