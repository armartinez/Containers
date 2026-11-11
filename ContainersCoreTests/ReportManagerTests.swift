//
//  ReportManagerTests.swift
//  ContainersCoreTests
//
//  Recording reports, and keeping the container system's list in step with the store.
//

import Foundation
import Testing

@testable import ContainersCore

@Suite("Report manager")
@MainActor
struct ReportManagerTests {
    private struct Failure: Error {}

    private func makeManager(in directory: TemporaryDirectory) async throws -> ReportManager {
        let containerSystem = MockContainerSystem()

        try await containerSystem.start(appRoot: directory.url)

        return ReportManager(testSystem: containerSystem)
    }

    @Test("Recorded report comes first")
    func recordedReportComesFirst() async throws {
        let directory = try TemporaryDirectory()

        defer { directory.remove() }

        let reportManager = try await makeManager(in: directory)

        await reportManager.record(kind: .image, name: "alpine", message: "The pull failed.", error: Failure())
        let latest = try #require(
            await reportManager.record(kind: .build, name: "nginx", message: "The build failed.", error: Failure())
        )

        #expect(reportManager.reports.first == latest)
        #expect(reportManager.reports.count == 2)
        #expect(reportManager.unreadCount == 2)
    }

    @Test("Marking read updates the list and the store")
    func markingReadUpdatesListAndStore() async throws {
        let directory = try TemporaryDirectory()

        defer { directory.remove() }

        let reportManager = try await makeManager(in: directory)
        let report = try #require(
            await reportManager.record(kind: .container, name: "web", message: "The container stopped.", error: Failure())
        )

        await reportManager.markRead(ids: [report.id])

        #expect(reportManager.isRead(id: report.id))
        #expect(reportManager.unreadCount == 0)

        await reportManager.refresh()

        #expect(reportManager.isRead(id: report.id))
    }

    @Test("Stopped system records nothing")
    func stoppedSystemRecordsNothing() async {
        let reportManager = ReportManager(testSystem: MockContainerSystem())

        let report = await reportManager.record(kind: .image, name: "alpine", message: "The pull failed.", error: Failure())

        #expect(report == nil)
        #expect(reportManager.reports.isEmpty)
    }
}
