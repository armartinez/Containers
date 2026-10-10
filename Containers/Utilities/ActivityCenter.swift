//
//  ActivityCenter.swift
//  Containers
//
//  Created by Axel Martinez on 12/09/2026.
//

import ContainerSystem
import Foundation
import Observation

@Observable
@MainActor
final class ActivityCenter {
    enum Kind: Hashable {
        case image
        case container
        case volume
    }

    /// An action the user took anywhere in the app. It executes until its
    /// work is done and the lists showing its items have read the outcome.
    @Observable
    @MainActor
    final class Activity: Identifiable {
        /// Can change once the work reveals it, as loading an archive does.
        fileprivate(set) var id: String
        fileprivate(set) var title: String
        fileprivate(set) var error: (any Error)?
        fileprivate(set) var reportID: String?
        fileprivate(set) var isStopped = false
        fileprivate(set) var startedAt: Date?
        /// A new one for every run, so a retry starts from nothing.
        fileprivate(set) var progress: ProgressObserver?

        fileprivate var task: Task<Void, Never>?

        /// A stopped run can take a moment to wind down, and must not speak
        /// for a retry begun since.
        @ObservationIgnored fileprivate var attempt = 0

        fileprivate let work: (Progress) async throws -> String?

        let kind: Kind
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
            kind: Kind,
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

    private(set) var activities: [Activity] = []

    /// The lists on screen, so an activity can wait for them to read its
    /// outcome before it stops executing.
    @ObservationIgnored private var listReloaders: [Kind: [UUID: () async -> Void]] = [:]

    private let reports: ReportManager

    init(reports: ReportManager) {
        self.reports = reports
    }

    func activities(ofKind kind: Kind) -> [Activity] {
        activities.filter { $0.kind == kind && !isSpent($0) }
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
        guard !activities.contains(where: { $0.id == id && $0.kind == kind }) else {
            return
        }

        let activity = Activity(
            id: id,
            kind: kind,
            title: title,
            subtitle: subtitle,
            failureTitle: failureTitle,
            canRetry: canRetry,
            showsProgress: showsProgress,
            work: work
        )

        activities.append(activity)
        run(activity)
    }

    func stop(_ id: String) {
        guard let activity = activity(id), activity.isExecuting else { return }

        activity.isStopped = true
        activity.task?.cancel()
    }

    func retry(_ id: String) {
        guard let activity = activity(id), activity.canRetry,
            !activity.isExecuting
        else {
            return
        }

        activity.error = nil
        activity.reportID = nil
        activity.isStopped = false

        run(activity)
    }

    func run(
        on id: String,
        kind: Kind,
        subtitle: String = "",
        failureTitle: String,
        showsProgress: Bool = true,
        work: @escaping () async throws -> Void
    ) {
        if let earlier = activity(id), !earlier.isExecuting {
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
        activities.contains { $0.id == id && $0.isExecuting }
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
        guard let activity = activity(id) else { return }

        activity.task?.cancel()
        drop(activity)
    }

    func forgetFailures(reportedAs reportIDs: Set<String>) {
        activities.removeAll { activity in
            !activity.isExecuting && activity.reportID.map(reportIDs.contains) == true
        }
    }

    /// Writing a report can fail, and a mark with none behind it can never be
    /// read away; clearing is the only way to be rid of it.
    func hasUnreportedFailures(ofKind kind: Kind) -> Bool {
        activities.contains(where: isUnreportedFailure(ofKind: kind))
    }

    func forgetUnreportedFailures(ofKind kind: Kind) {
        activities.removeAll(where: isUnreportedFailure(ofKind: kind))
    }

    /// A failure's mark leads to its report, so once that is read it goes.
    private func isSpent(_ activity: Activity) -> Bool {
        guard activity.error != nil, let reportID = activity.reportID else {
            return false
        }

        return reports.isRead(reportID)
    }

    private func isUnreportedFailure(ofKind kind: Kind) -> (Activity) -> Bool {
        { $0.kind == kind && $0.error != nil && $0.reportID == nil }
    }

    private func activity(_ id: String) -> Activity? {
        activities.first { $0.id == id }
    }

    private func run(_ activity: Activity) {
        activity.attempt += 1
        activity.startedAt = Date()

        let attempt = activity.attempt
        let reports = reports
        let progress = Progress.discreteProgress(totalUnitCount: 0)

        activity.progress = ProgressObserver(progress)
        activity.task = Task { [weak self] in
            do {
                let made = try await activity.work(progress)

                guard activity.attempt == attempt else { return }

                if let made, made != activity.id {
                    activity.id = made
                    activity.title = made
                }

                await self?.reloadLists(ofKind: activity.kind)

                self?.drop(activity)
            } catch {
                guard activity.attempt == attempt, !activity.isStopped else { return }

                // A failed action can still have changed its item.
                await self?.reloadLists(ofKind: activity.kind)

                guard activity.attempt == attempt, !activity.isStopped else { return }

                activity.error = error

                let entry = await reports.record(
                    kind: activity.reportKind(for: error),
                    name: activity.title,
                    message: activity.failureTitle,
                    error: error,
                    startedAt: activity.startedAt
                )

                activity.reportID = entry?.id
            }
        }
    }

    /// A list that isn't on screen reads everything again when it appears.
    /// Unstructured, so stopping the activity can't cancel a list's load
    /// and have it report a failure.
    private func reloadLists(ofKind kind: Kind) async {
        let reloaders = listReloaders[kind, default: [:]].values

        await Task {
            for reload in reloaders {
                await reload()
            }
        }.value
    }

    private func drop(_ activity: Activity) {
        activities.removeAll { $0 === activity }
    }
}

// MARK: - Rows

extension ActivityCenter {
    /// Attaches each row's work, or else an unread failure reported under the
    /// name `reportName` gives it, where it gives one.
    ///
    /// Given `pendingRow`, work of `kind` with no row yet gets one, keyed by
    /// the item it will make, so it becomes that item's row in place.
    func marked<Row: ActivityRow>(
        _ rows: [Row],
        ofKind kind: Kind,
        reportName: (Row) -> String?,
        reportKinds: Set<Report.Kind>,
        pendingRow: ((ActivitySnapshot) -> Row)? = nil
    ) -> [Row] {
        let working = activities(ofKind: kind)

        let marked = rows.map { row in
            var row = row

            if let activity = working.first(where: { $0.id == row.id }) {
                row.activity = ActivitySnapshot(activity)
            } else if let name = reportName(row),
                let report = reports.latestReport(named: name, ofKind: reportKinds),
                !report.isRead
            {
                // Keyed by the row: an image is reported under the reference
                // asked for, but its row is known by the resolved one.
                row.activity = ActivitySnapshot(report: report, id: row.id)
            }

            return row
        }

        guard let pendingRow else { return marked }

        let markedIDs = Set(marked.map(\.id))
        let pending =
            working
            .filter { !markedIDs.contains($0.id) }
            .map { pendingRow(ActivitySnapshot($0)) }

        return pending + marked
    }
}
