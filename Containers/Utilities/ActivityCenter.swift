//
//  ActivityCenter.swift
//  Containers
//
//  Created by Axel Martinez on 12/09/2026.
//

import ContainersCore
import Foundation
import Observation

/// An action the user took anywhere in the app. It executes until its
/// work is done and the lists showing its items have read the outcome.
@Observable
@MainActor
final class ContainerSystemTask: Identifiable {
    /// Can change once the work reveals it, as loading an archive does.
    fileprivate(set) var id: String
    fileprivate(set) var title: String
    fileprivate(set) var error: (any Error)?
    fileprivate(set) var reportID: String?
    fileprivate(set) var isStopped = false
    fileprivate(set) var startedAt: Date?
    /// A new one for every run, so a retry starts from nothing.
    fileprivate(set) var progress: ProgressObserver?

    fileprivate var execution: Task<Void, Never>?

    /// A stopped run can take a moment to wind down, and must not speak
    /// for a retry begun since.
    @ObservationIgnored fileprivate var attempt = 0

    fileprivate let work: (Progress) async throws -> String?

    let kind: ActivityCenter.Kind
    let subtitle: String
    let canRetry: Bool
    let failureTitle: String
    /// Off where the item's own state already shows the work under way.
    let showsProgress: Bool

    /// One that succeeded is dropped, so only a failure or a stop ends it.
    var isExecuting: Bool {
        error == nil && !isStopped
    }

    fileprivate init(
        id: String,
        kind: ActivityCenter.Kind,
        title: String,
        subtitle: String,
        failureTitle: String,
        canRetry: Bool,
        showsProgress: Bool,
        work: @escaping (Progress) async throws -> String?
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.failureTitle = failureTitle
        self.canRetry = canRetry
        self.showsProgress = showsProgress
        self.work = work
    }

    fileprivate func reportKind(for error: any Error) -> Report.Kind {
        if error is BuildFailure { return .build }

        switch kind {
        case .image: return .image
        case .container: return .container
        case .volume: return .volume
        }
    }
}

@Observable
@MainActor
final class ActivityCenter {
    enum Kind: Hashable {
        case image
        case container
        case volume
    }

    private(set) var tasks: [ContainerSystemTask] = []

    /// The lists on screen, so a task can wait for them to read its
    /// outcome before it stops executing.
    @ObservationIgnored private var listReloaders: [Kind: [UUID: () async -> Void]] = [:]

    private let reports: ReportManager

    init(reports: ReportManager) {
        self.reports = reports
    }

    func tasks(ofKind kind: Kind) -> [ContainerSystemTask] {
        tasks.filter { $0.kind == kind && !isSpent($0) }
    }

    /// Does nothing if the same work is already under way. `work` answers
    /// with what it made, where that isn't known in advance.
    func start(
        id: String,
        kind: Kind,
        title: String,
        subtitle: String = "",
        failureTitle: String,
        canRetry: Bool = true,
        showsProgress: Bool = true,
        work: @escaping (Progress) async throws -> String?
    ) {
        guard !tasks.contains(where: { $0.id == id && $0.kind == kind }) else {
            return
        }

        let task = ContainerSystemTask(
            id: id,
            kind: kind,
            title: title,
            subtitle: subtitle,
            failureTitle: failureTitle,
            canRetry: canRetry,
            showsProgress: showsProgress,
            work: work
        )

        tasks.append(task)
        run(task)
    }

    func stop(_ id: String) {
        guard let task = task(id), task.isExecuting else { return }

        task.isStopped = true
        task.execution?.cancel()
    }

    func retry(_ id: String) {
        guard let task = task(id), task.canRetry,
            !task.isExecuting
        else {
            return
        }

        task.error = nil
        task.reportID = nil
        task.isStopped = false

        run(task)
    }

    func run(
        on id: String,
        kind: Kind,
        subtitle: String = "",
        failureTitle: String,
        showsProgress: Bool = true,
        work: @escaping () async throws -> Void
    ) {
        if let earlier = task(id), !earlier.isExecuting {
            drop(earlier)
        }

        start(
            id: id,
            kind: kind,
            title: id,
            subtitle: subtitle,
            failureTitle: failureTitle,
            showsProgress: showsProgress
        ) { _ in
            try await work()
            return nil
        }
    }

    func isWorking(on id: String) -> Bool {
        tasks.contains { $0.id == id && $0.isExecuting }
    }

    /// Registers a list on screen that shows items of `kind`. Remove it
    /// with `removeListReloader(_:ofKind:)` once the list goes.
    func addListReloader(_ id: UUID, ofKind kind: Kind, reload: @escaping () async -> Void) {
        listReloaders[kind, default: [:]][id] = reload
    }

    func removeListReloader(_ id: UUID, ofKind kind: Kind) {
        listReloaders[kind]?[id] = nil
    }

    func remove(_ id: String) {
        guard let task = task(id) else { return }

        task.execution?.cancel()
        drop(task)
    }

    func forgetFailures(reportedAs reportIDs: Set<String>) {
        tasks.removeAll { task in
            !task.isExecuting && task.reportID.map(reportIDs.contains) == true
        }
    }

    /// A failure's mark leads to its report, so once that is read it goes.
    private func isSpent(_ task: ContainerSystemTask) -> Bool {
        guard task.error != nil, let reportID = task.reportID else {
            return false
        }

        return reports.isRead(reportID)
    }

    private func task(_ id: String) -> ContainerSystemTask? {
        tasks.first { $0.id == id }
    }

    private func run(_ task: ContainerSystemTask) {
        task.attempt += 1
        task.startedAt = Date()

        let attempt = task.attempt
        let reports = reports
        let progress = Progress.discreteProgress(totalUnitCount: 0)

        task.progress = ProgressObserver(progress)
        task.execution = Task { [weak self] in
            do {
                let made = try await task.work(progress)

                guard task.attempt == attempt else { return }

                if let made, made != task.id {
                    task.id = made
                    task.title = made
                }

                await self?.reloadLists(ofKind: task.kind)

                self?.drop(task)
            } catch {
                guard task.attempt == attempt, !task.isStopped else { return }

                // A failed action can still have changed its item.
                await self?.reloadLists(ofKind: task.kind)

                guard task.attempt == attempt, !task.isStopped else { return }

                task.error = error

                let entry = await reports.record(
                    kind: task.reportKind(for: error),
                    name: task.title,
                    message: task.failureTitle,
                    error: error,
                    startedAt: task.startedAt
                )

                task.reportID = entry?.id
            }
        }
    }

    /// A list that isn't on screen reads everything again when it appears.
    /// Unstructured, so stopping the task can't cancel a list's load
    /// and have it report a failure.
    private func reloadLists(ofKind kind: Kind) async {
        let reloaders = listReloaders[kind, default: [:]].values

        await Task {
            for reload in reloaders {
                await reload()
            }
        }.value
    }

    private func drop(_ task: ContainerSystemTask) {
        tasks.removeAll { $0 === task }
    }
}

// MARK: - Rows

extension ActivityCenter {
    /// Attaches each row's work, or else an unread failure reported under the
    /// name `reportName` gives it, where it gives one.
    ///
    /// Given `pendingRow`, work of `kind` with no row yet gets one, keyed by
    /// the item it will make, so it becomes that item's row in place.
    func marked<Row: TaskRow>(
        _ rows: [Row],
        ofKind kind: Kind,
        reportName: (Row) -> String?,
        reportKinds: Set<Report.Kind>,
        pendingRow: ((ContainerSystemTask.Snapshot) -> Row)? = nil
    ) -> [Row] {
        let working = tasks(ofKind: kind)

        let marked = rows.map { row in
            var row = row

            if let task = working.first(where: { $0.id == row.id }) {
                row.task = ContainerSystemTask.Snapshot(task)
            } else if let name = reportName(row),
                let report = reports.latestReport(named: name, ofKind: reportKinds),
                !report.isRead
            {
                // Keyed by the row: an image is reported under the reference
                // asked for, but its row is known by the resolved one.
                row.task = ContainerSystemTask.Snapshot(report: report, id: row.id)
            }

            return row
        }

        guard let pendingRow else { return marked }

        let markedIDs = Set(marked.map(\.id))
        let pending =
            working
            .filter { !markedIDs.contains($0.id) }
            .map { pendingRow(ContainerSystemTask.Snapshot($0)) }

        return pending + marked
    }
}
