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
    /// the default registry from the system's settings, `library/` for Docker
    /// Hub's official images, and the `latest` tag.
    ///
    /// - Parameters:
    ///   - reference: The reference as typed.
    ///   - registry: The registry for a reference that doesn't name one.
    /// - Returns: The complete reference.
    /// - Throws: An error if the text isn't a reference.
    public static func normalized(_ reference: String, registry: String = DefaultsStore.get(key: .registryDomain)) throws -> Reference {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        var parsed = try parse(trimmed)

        // The init image is used as configured, so a local build of it can stand in.
        if parsed.domain == nil, trimmed != DefaultsStore.get(key: .defaultInitImage) {
            parsed = try parse("\(registry)/\(trimmed)")
        }

        parsed.normalize()

        return parsed
    }
}
