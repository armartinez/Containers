//
//  EntityNameTests.swift
//  ContainerSystemTests
//
//  The names a container or volume is allowed to carry.
//

import Foundation
import Testing

@testable import ContainerSystem

@Suite("Entity name")
struct EntityNameTests {

    @Test(
        "Valid names are accepted",
        arguments: ["web", "my-app", "db_1", "a.b-c_d", "A", "9lives"]
    )
    func acceptsValidNames(_ name: String) {
        #expect(EntityName.isValid(name))
    }

    @Test(
        "Bad first character is rejected",
        arguments: ["", "-web", "_web", ".web", "/web", " web"]
    )
    func rejectsBadStarts(_ name: String) {
        #expect(!EntityName.isValid(name))
    }

    @Test(
        "Disallowed characters are rejected",
        arguments: ["my app", "web/1", "web:latest", "wéb", "web!", "a\nb"]
    )
    func rejectsBadCharacters(_ name: String) {
        #expect(!EntityName.isValid(name))
    }

    @Test("Length limit")
    func enforcesLength() {
        let atLimit = String(repeating: "a", count: EntityName.maximumLength)
        let overLimit = String(
            repeating: "a",
            count: EntityName.maximumLength + 1
        )

        #expect(EntityName.isValid(atLimit))
        #expect(!EntityName.isValid(overLimit))
    }

    @Test(
        "Sanitize removes disallowed characters",
        arguments: [
            ("my app", "myapp"),
            ("--web", "web"),
            ("__db.1", "db.1"),
            ("web:latest", "weblatest"),
            ("...9lives", "9lives"),
        ]
    )
    func sanitizes(_ input: String, _ expected: String) {
        #expect(EntityName.valid(from: input) == expected)
    }

    @Test("Sanitize truncates long names")
    func sanitizeTruncates() {
        let sanitized = EntityName.valid(
            from: String(repeating: "a", count: EntityName.maximumLength + 50)
        )

        #expect(sanitized.count == EntityName.maximumLength)
        #expect(EntityName.isValid(sanitized))
    }

    @Test(
        "Sanitize returns a valid name or nil",
        arguments: [
            "my app", "--web", "web:latest", "...", "!!!", "", "café",
            "9lives", "___",
        ]
    )
    func sanitizeYieldsUsableName(_ input: String) {
        let sanitized = EntityName.valid(from: input)

        // The form's fallback relies on this: anything non-empty that comes
        // back out can be submitted as-is.
        #expect(sanitized.isEmpty || EntityName.isValid(sanitized))
    }
}
