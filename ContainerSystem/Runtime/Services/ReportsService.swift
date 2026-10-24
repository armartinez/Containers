//
//  ReportsService.swift
//  Containers
//
//  Keeps the reports of failed work.
//
//  Created by Axel Martinez on 24/10/2026.
//

import Foundation
import Logging

/// Service for the reports generated from tasks, kept in a `ReportStore` under the app root.
actor ReportsService {
    private static let folderName = "reports"

    private let log: Logger
    private let store: ReportStore

    /// Callbacks to invoke with the reports, most recent first, whenever they change.
    private var changeCallbacks: [@Sendable @MainActor ([Report]) -> Void] = []

    init(appRoot: URL, log: Logger) throws {
        self.log = log
        self.store = try ReportStore(root: appRoot.appendingPathComponent(Self.folderName))
    }

    @discardableResult
    func record(
        level: Report.Level,
        kind: Report.Kind,
        name: String,
        message: String,
        body: String,
        startedAt: Date?
    ) async throws -> Report {
        let report = try await store.record(
            level: level,
            kind: kind,
            name: name,
            message: message,
            body: body,
            startedAt: startedAt
        )

        await notifyChange()

        return report
    }

    /// Register a callback to be invoked with the reports whenever they change.
    func addChangeCallback(_ callback: @escaping @Sendable @MainActor ([Report]) -> Void) {
        changeCallbacks.append(callback)
    }

    /// Most recent first.
    func list() async -> [Report] {
        await store.list()
    }

    func get(id: String) async -> Report? {
        await store.entry(for: id)
    }

    func body(of id: String) async throws -> String {
        try await store.body(of: id)
    }

    func markRead(_ ids: [String]) async {
        guard !ids.isEmpty else { return }

        await store.markRead(ids)
        await notifyChange()
    }

    func delete(ids: [String]) async {
        guard !ids.isEmpty else { return }

        await store.remove(ids)
        await notifyChange()
    }

    /// Deletes the reports about things that no longer exist, such as deleted images.
    ///
    /// - Parameters:
    ///   - names: The names of what the work was on.
    ///   - kinds: Every kind of report they can have.
    func delete(named names: [String], ofKind kinds: Set<Report.Kind>) async {
        let names = Set(names)
        let ids = await store.list()
            .filter { kinds.contains($0.kind) && names.contains($0.name) }
            .map(\.id)

        await delete(ids: ids)
    }

    nonisolated func url(for id: String) -> URL {
        store.url(for: id)
    }

    /// Awaited rather than scheduled, so callers find the reports updated as soon as a change returns.
    private func notifyChange() async {
        let reports = await store.list()

        for callback in changeCallbacks {
            await callback(reports)
        }
    }
}
