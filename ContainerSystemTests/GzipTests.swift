//
//  GzipTests.swift
//  ContainerSystemTests
//

import Foundation
import Testing

@testable import ContainerSystem

@Suite("Gzip")
struct GzipTests {
    @Test("Round trip")
    func roundTrip() throws {
        let text = "Step 1/3 : FROM alpine\nété ✓\n"
        let data = try #require(Gzip.compressed(text))

        #expect(Gzip.text(of: data) == text)
    }

    @Test("Empty round trip")
    func emptyRoundTrip() throws {
        let data = try #require(Gzip.compressed(""))

        #expect(Gzip.text(of: data) == "")
    }

    @Test("Plain text is rejected")
    func plainTextIsRejected() {
        #expect(Gzip.text(of: Data("plain text that was never compressed".utf8)) == nil)
    }
}
