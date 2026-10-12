//
//  Reference+Normalized.swift
//  Containers
//
//  Created by Axel Martinez on 03/10/2026.
//

import ContainerizationOCI
import Foundation

extension Reference {
    /// Parses a reference as typed, filling in what a short name leaves out:
    /// Docker Hub as the registry, `library/` for its official images, and
    /// the `latest` tag.
    public static func normalized(_ reference: String) throws -> Reference {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        var parsed = try parse(trimmed)

        if parsed.domain == nil {
            parsed = try parse("docker.io/\(trimmed)")
        }

        parsed.normalize()

        return parsed
    }
}
