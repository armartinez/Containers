//
//  ReportManager.swift
//  Containers
//
//  Created by Axel Martinez on 16/09/2026.
//

import Foundation
import Logging
import Observation

/// Records failed work and keeps the reports the app shows. Every instance shares the runtime's reports.
@Observable
@MainActor
public final class ReportManager {
    let runtime: ContainerRuntime

    private let logger: Logger
    private let folder: String

    /// The most recent first.
    public private(set) var reports: [Report] {
        get { runtime.reports }
        set { runtime.reports = newValue }
    }

    public convenience init() {
        self.init(runtime: ContainerRuntime.shared)
    }

    init(runtime: ContainerRuntime, folder: String = "reports") {
        self.runtime = runtime
        self.logger = Logger(label: "app.containers.manager.report")
        self.folder = folder
    }

    /// Doesn't throw: failing to write a report isn't worth a second failure.
    /// A container's own output isn't copied in, as its Logs already hold it.
    @discardableResult
    public func record(
        level: Report.Level = .error,
        kind: Report.Kind,
        name: String,
        message: String,
        error: any Error,
        startedAt: Date? = nil
    ) async -> Report? {
        guard let store = try? store() else { return nil }

        do {
            let entry = try await store.record(
                level: level,
                kind: kind,
                name: name,
                message: message,
                body: Self.body(for: error),
                startedAt: startedAt
            )

            reports.insert(entry, at: 0)

            return entry
        } catch {
            logger.error("Couldn’t write the report: \(error)")

            return nil
        }
    }

    public var unreadCount: Int {
        reports.count { !$0.isRead }
    }

    public func markRead(_ ids: [String]) async {
        guard let store = try? store() else { return }

        let unread = Set(
            reports.filter { !$0.isRead && ids.contains($0.id) }.map(\.id)
        )

        guard !unread.isEmpty else { return }

        await store.markRead(Array(unread))

        reports = reports.map { report in
            guard unread.contains(report.id) else { return report }

            return Report(
                id: report.id,
                date: report.date,
                endDate: report.endDate,
                level: report.level,
                kind: report.kind,
                name: report.name,
                message: report.message,
                isRead: true
            )
        }
    }

    public func refresh() async {
        guard let store = try? store() else { return }

        reports = await store.list()
    }

    /// `kinds` lists every kind the item is filed under: an image is reported
    /// both as `.image` and as `.build`.
    public func latestReport(named name: String, ofKind kinds: Set<Report.Kind>) -> Report? {
        reports.first { kinds.contains($0.kind) && $0.name == name }
    }

    public func reports(named name: String, ofKind kinds: Set<Report.Kind>) -> [Report] {
        reports.filter { kinds.contains($0.kind) && $0.name == name }
    }

    public func isRead(_ id: String) -> Bool {
        reports.first { $0.id == id }?.isRead ?? true
    }

    public func entry(for id: String) async -> Report? {
        guard let store = try? store() else { return nil }

        return await store.entry(for: id)
    }

    public func body(of id: String) async -> String? {
        guard let store = try? store() else { return nil }

        return try? await store.body(of: id)
    }

    public func remove(_ ids: [String]) async {
        guard let store = try? store() else { return }

        await store.remove(ids)

        reports.removeAll { ids.contains($0.id) }
    }

    /// For items that were deleted, whose reports nothing can lead to any more.
    public func remove(named names: [String], ofKind kinds: Set<Report.Kind>) async {
        let names = Set(names)
        let ids =
            reports
            .filter { kinds.contains($0.kind) && names.contains($0.name) }
            .map(\.id)

        guard !ids.isEmpty else { return }

        await remove(ids)
    }

    public func url(for id: String) -> URL? {
        try? store().url(for: id)
    }

    private func store() throws -> ReportStore {
        if let store = runtime.reportStore { return store }

        let store = try ReportStore(root: runtime.getAppRoot().appendingPathComponent(folder))

        runtime.reportStore = store

        return store
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
