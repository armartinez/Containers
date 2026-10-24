//
//  ReportManager.swift
//  Containers
//
//  Created by Axel Martinez on 16/09/2026.
//

import Foundation
import Logging
import Observation

/// A manager that records failed work, and keeps the reports it leaves.
///
/// A report keeps what went wrong with a pull, a build or a container after the work ends, so people
/// can review it later. Reports are saved in the container system's storage folder.
@Observable
@MainActor
public final class ReportManager {
    let runtime: ContainerRuntime

    private let logger: Logger

    /// The reports, most recent first.
    public var reports: [Report] {
        runtime.reports
    }

    /// Creates a manager for the shared container system.
    public init() {
        self.runtime = ContainerRuntime.shared
        self.logger = Logger(label: "app.containers.manager.report")
    }

    #if DEBUG
    /// Creates a manager for the given runtime, so tests can use a runtime of their own.
    init(testRuntime: ContainerRuntime) {
        self.runtime = testRuntime
        self.logger = Logger(label: "app.containers.manager.report.test")
    }
    #endif

    /// Records a report of failed work.
    ///
    /// This method doesn't throw: if the report can't be saved, it returns `nil`. A container's own
    /// output isn't copied into its report, because the container's logs already keep it.
    ///
    /// - Parameters:
    ///   - level: How serious the problem is.
    ///   - kind: The kind of work that failed.
    ///   - name: The name of what the work was on, such as an image's reference or a container's ID.
    ///   - message: A short description of what went wrong.
    ///   - error: The error the work threw, which the report keeps in full.
    ///   - startedAt: When the work started, or `nil` if the report covers only the moment it failed.
    /// - Returns: The new report, or `nil` if it couldn't be saved.
    @discardableResult
    public func record(
        level: Report.Level = .error,
        kind: Report.Kind,
        name: String,
        message: String,
        error: any Error,
        startedAt: Date? = nil
    ) async -> Report? {
        do {
            return try await runtime.getReportsService()
                .record(
                    level: level,
                    kind: kind,
                    name: name,
                    message: message,
                    body: Self.body(for: error),
                    startedAt: startedAt
                )
        } catch {
            logger.error("Couldn’t write the report: \(error)")

            return nil
        }
    }

    /// The number of reports that haven't been read.
    public var unreadCount: Int {
        reports.count { !$0.isRead }
    }

    /// Marks reports as read.
    ///
    /// - Parameter ids: The IDs of the reports to mark.
    public func markRead(_ ids: [String]) async {
        let ids = Set(ids)
        let unread = reports.filter { !$0.isRead && ids.contains($0.id) }.map(\.id)

        guard !unread.isEmpty, let service = service() else { return }

        await service.markRead(unread)
    }

    /// Reloads the reports from the storage folder.
    public func refresh() async {
        guard let service = service() else { return }

        runtime.reports = await service.list()
    }

    /// Returns the most recent report about something.
    ///
    /// - Parameters:
    ///   - name: The name of what the work was on.
    ///   - kinds: Every kind of report it can have. An image, for example, has both image and build reports.
    /// - Returns: The report, or `nil` if there isn't one.
    public func latestReport(named name: String, ofKind kinds: Set<Report.Kind>) -> Report? {
        reports.first { kinds.contains($0.kind) && $0.name == name }
    }

    /// Returns the reports about something, most recent first.
    ///
    /// - Parameters:
    ///   - name: The name of what the work was on.
    ///   - kinds: Every kind of report it can have.
    /// - Returns: The reports.
    public func reports(named name: String, ofKind kinds: Set<Report.Kind>) -> [Report] {
        reports.filter { kinds.contains($0.kind) && $0.name == name }
    }

    /// Returns a Boolean value that indicates whether a report has been read.
    ///
    /// - Parameter id: The report's ID.
    /// - Returns: `true` if the report has been read or doesn't exist.
    public func isRead(_ id: String) -> Bool {
        reports.first { $0.id == id }?.isRead ?? true
    }

    /// Returns a report, read from the storage folder.
    ///
    /// - Parameter id: The report's ID.
    /// - Returns: The report, or `nil` if it doesn't exist.
    public func get(id: String) async -> Report? {
        guard let service = service() else { return nil }

        return await service.get(id: id)
    }

    /// Returns the full text of a report.
    ///
    /// - Parameter id: The report's ID.
    /// - Returns: The text, or `nil` if it can't be read.
    public func body(of id: String) async -> String? {
        guard let service = service() else { return nil }

        do {
            return try await service.body(of: id)
        } catch {
            logger.error("Couldn’t read the report \(id): \(error)")

            return nil
        }
    }

    /// Deletes reports.
    ///
    /// - Parameter ids: The IDs of the reports to delete.
    public func delete(ids: [String]) async {
        await service()?.delete(ids: ids)
    }

    /// Returns the location of a report's file, for showing it in the Finder.
    ///
    /// - Parameter id: The report's ID.
    /// - Returns: The file's URL, or `nil` if the storage folder isn't available.
    public func url(for id: String) -> URL? {
        service()?.url(for: id)
    }

    private func service() -> ReportsService? {
        do {
            return try runtime.getReportsService()
        } catch {
            logger.error("Couldn’t reach the reports: \(error)")

            return nil
        }
    }

    static func body(for error: any Error) -> String {
        if let failure = error as? BuildFailure {
            return """
                \(failure.message)

                \(failure.transcript)
                """
        }

        let described = String(describing: error)
        let localized = error.localizedDescription

        // Often the localized text wrapped in the case name, so one is enough.
        guard !described.contains(localized), !localized.contains(described)
        else {
            return localized
        }

        return """
            \(localized)

            \(described)
            """
    }
}
