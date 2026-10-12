//
//  ReportStoreTests.swift
//  ContainerSystemTests
//
//  Keeping a report, and reading it back.
//

import Foundation
import Testing

@testable import ContainerSystem

@Suite("Report store")
struct ReportStoreTests {
    /// A folder of its own for each test, so that none of them reads what
    /// another wrote.
    private func makeStore() throws -> (ReportStore, URL) {
        let root = URL.temporaryDirectory
            .appendingPathComponent("reports-\(UUID().uuidString)")

        return (try ReportStore(root: root), root)
    }

    @Test("Record and list")
    func recordsAndLists() async throws {
        let (store, root) = try makeStore()

        defer { try? FileManager.default.removeItem(at: root) }

        let started = Date(timeIntervalSinceNow: -12)
        let written = try await store.record(
            level: .error,
            kind: .build,
            name: "nginx:latest",
            message: "The image couldn’t be built.",
            body: "step 3/4 failed",
            startedAt: started
        )

        let listed = try #require(await store.list().first)

        #expect(listed == written)
        #expect(listed.kind == .build)
        #expect(listed.level == .error)
        #expect(listed.name == "nginx:latest")
        #expect(listed.message == "The image couldn’t be built.")
        #expect(abs(listed.date.timeIntervalSince(started)) < 0.001)
        #expect(listed.endDate >= listed.date)
    }

    /// The account is read from the file rather than from the manifest, which
    /// is the whole point of keeping the two apart.
    @Test("Body round trip")
    func readsBodyBack() async throws {
        let (store, root) = try makeStore()

        defer { try? FileManager.default.removeItem(at: root) }

        let transcript = (1...500)
            .map { "#\($0) RUN apt-get install nothing" }
            .joined(separator: "\n")

        let written = try await store.record(
            level: .error,
            kind: .build,
            name: "nginx:latest",
            message: "The image couldn’t be built.",
            body: transcript,
            startedAt: nil
        )

        #expect(try await store.body(of: written.id) == transcript)
    }

    /// Deflated as Xcode deflates its own, so that anything that reads a gzip
    /// file can read one of these.
    @Test("Body is gzipped")
    func keepsBodyDeflated() async throws {
        let (store, root) = try makeStore()

        defer { try? FileManager.default.removeItem(at: root) }

        let body = String(repeating: "the builder said something\n", count: 400)
        let written = try await store.record(
            level: .warning,
            kind: .image,
            name: "nginx:latest",
            message: "The image couldn’t be fetched.",
            body: body,
            startedAt: nil
        )

        let data = try Data(contentsOf: store.url(for: written.id))

        #expect(data.prefix(2) == Data([0x1f, 0x8b]))
        #expect(data.count < body.utf8.count / 2)
        #expect(Gzip.text(of: data) == body)
    }

    @Test("Remove deletes report")
    func removesReport() async throws {
        let (store, root) = try makeStore()

        defer { try? FileManager.default.removeItem(at: root) }

        let written = try await store.record(
            level: .error,
            kind: .container,
            name: "web",
            message: "The container couldn’t be started.",
            body: "the boot loader is invalid",
            startedAt: nil
        )

        await store.remove([written.id])

        #expect(await store.list().isEmpty)
        #expect(
            !FileManager.default.fileExists(
                atPath: store.url(for: written.id).path
            )
        )
    }

    /// The count a section carries is kept with the reports themselves, so it
    /// is still right after the app has been closed and opened again.
    @Test("Read state persists")
    func keepsWhatHasBeenRead() async throws {
        let (store, root) = try makeStore()

        defer { try? FileManager.default.removeItem(at: root) }

        let written = try await store.record(
            level: .error,
            kind: .container,
            name: "web",
            message: "The container couldn’t be started.",
            body: "the boot loader is invalid",
            startedAt: nil
        )

        #expect(await store.entry(for: written.id)?.isRead == false)

        await store.markRead([written.id])

        #expect(await store.entry(for: written.id)?.isRead == true)
        #expect(try await ReportStore(root: root).list().first?.isRead == true)
    }

    /// Reports outlive the app, so a store opened again reads what an earlier
    /// one wrote rather than starting afresh.
    @Test("Reopened store keeps reports")
    func readsWhatAnEarlierStoreWrote() async throws {
        let (store, root) = try makeStore()

        defer { try? FileManager.default.removeItem(at: root) }

        let written = try await store.record(
            level: .error,
            kind: .volume,
            name: "data",
            message: "The volume couldn’t be created.",
            body: "no space left on device",
            startedAt: nil
        )

        let reopened = try ReportStore(root: root)

        #expect(await reopened.entry(for: written.id) == written)
        #expect(try await reopened.body(of: written.id) == "no space left on device")
    }
}

@Suite("Report body")
@MainActor
struct ReportBodyTests {
    /// The same error twice, once with the name of its case around it, is what
    /// most of these are: a report says it once.
    @Test("Wrapped error appears once")
    func doesNotRepeatTheError() {
        // What a `ContainerizationError` is: its case, then the message.
        struct Wrapped: LocalizedError, CustomStringConvertible {
            var errorDescription: String? {
                "failed to start container: no kernel"
            }

            var description: String {
                "internalError: \"failed to start container: no kernel\""
            }
        }

        let body = ReportManager.body(for: Wrapped())

        #expect(body == "failed to start container: no kernel")
    }

    /// Where the two say different things, both are worth keeping.
    @Test("Distinct descriptions are both kept")
    func keepsBothWhereTheyDiffer() {
        struct Detailed: LocalizedError {
            var errorDescription: String? { "The container couldn’t be started." }
        }

        let body = ReportManager.body(for: Detailed())

        #expect(body.contains("The container couldn’t be started."))
        #expect(body.contains("Detailed"))
    }
}
