//
//  ReportManagerTests.swift
//  ContainerSystemTests
//
//  Recording reports, and keeping the runtime's list in step with the store.
//

import Foundation
import Testing

@testable import ContainerSystem

@Suite("Report manager")
@MainActor
struct ReportManagerTests {
    private struct Failure: Error {}

    private func makeManager(in directory: TemporaryDirectory) async throws -> ReportManager {
        let runtime = MockContainerRuntime()

        try await SystemManager(testRuntime: runtime).start(appRoot: directory.url)

        return ReportManager(testRuntime: runtime)
    }

    @Test("Recorded report comes first")
    func recordedReportComesFirst() async throws {
        let directory = try TemporaryDirectory()

        defer { directory.remove() }

        let manager = try await makeManager(in: directory)

        await manager.record(kind: .image, name: "alpine", message: "The pull failed.", error: Failure())
        let latest = try #require(
            await manager.record(kind: .build, name: "nginx", message: "The build failed.", error: Failure())
        )

        #expect(manager.reports.first == latest)
        #expect(manager.reports.count == 2)
        #expect(manager.unreadCount == 2)
    }

    @Test("Marking read updates the list and the store")
    func markingReadUpdatesListAndStore() async throws {
        let directory = try TemporaryDirectory()

        defer { directory.remove() }

        let manager = try await makeManager(in: directory)
        let report = try #require(
            await manager.record(kind: .container, name: "web", message: "The container stopped.", error: Failure())
        )

        await manager.markRead([report.id])

        #expect(manager.isRead(report.id))
        #expect(manager.unreadCount == 0)

        await manager.refresh()

        #expect(manager.isRead(report.id))
    }

    @Test("Stopped system records nothing")
    func stoppedSystemRecordsNothing() async {
        let manager = ReportManager(testRuntime: MockContainerRuntime())

        let report = await manager.record(kind: .image, name: "alpine", message: "The pull failed.", error: Failure())

        #expect(report == nil)
        #expect(manager.reports.isEmpty)
    }
}
