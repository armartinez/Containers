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

    /// Work under way anywhere in the app.
    @Observable
    @MainActor
    final class Activity: Identifiable {
        /// Can change once the work reveals it, as loading an archive does.
        fileprivate(set) var id: String
        fileprivate(set) var title: String
        fileprivate(set) var error: (any Error)?
        fileprivate(set) var reportID: String?
        fileprivate(set) var isStopped = false
        fileprivate(set) var isFinished = false
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

        var hasEnded: Bool {
            error != nil || isStopped
        }

        fileprivate init(
            id: String,
            kind: Kind,
            title: String,
            subtitle: String,
            failureTitle: String,
            canRetry: Bool,
            work: @escaping (Progress) async throws -> String?
        ) {
            self.id = id
            self.kind = kind
            self.title = title
            self.subtitle = subtitle
            self.failureTitle = failureTitle
            self.canRetry = canRetry
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
    /// Lists watch this to know when to read what they show again.
    private(set) var endings: Int = 0

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
            work: work
        )

        activities.append(activity)
        run(activity)
    }

    func stop(_ id: String) {
        guard let activity = activity(id), !activity.hasEnded else { return }

        activity.isStopped = true
        activity.task?.cancel()
    }

    func retry(_ id: String) {
        guard let activity = activity(id), activity.canRetry,
            activity.hasEnded
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
        work: @escaping () async throws -> Void
    ) {
        if let earlier = activity(id), earlier.hasEnded {
            drop(earlier)
        }

        start(
            id: id,
            kind: kind,
            title: id,
            subtitle: subtitle,
            failureTitle: failureTitle
        ) { _ in
            try await work()
            return nil
        }
    }

    func isWorking(on id: String) -> Bool {
        activities.contains { $0.id == id && !$0.hasEnded && !$0.isFinished }
    }

    func remove(_ id: String) {
        guard let activity = activity(id) else { return }

        activity.task?.cancel()
        drop(activity)
    }

    func forgetFailures(reportedAs reportIDs: Set<String>) {
        activities.removeAll { activity in
            activity.hasEnded && activity.reportID.map(reportIDs.contains) == true
        }
    }

    func forgetFinished(ofKind kind: Kind) {
        activities.removeAll { $0.kind == kind && $0.isFinished }
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

                activity.isFinished = true

                self?.endings += 1

                // For work that finished while its list wasn't on screen to
                // let go of it.
                try? await Task.sleep(for: .seconds(1))

                self?.drop(activity)
            } catch {
                guard activity.attempt == attempt else { return }

                guard !activity.isStopped else { return }

                activity.error = error

                let entry = await reports.record(
                    kind: activity.reportKind(for: error),
                    name: activity.title,
                    message: activity.failureTitle,
                    error: error,
                    startedAt: activity.startedAt
                )

                activity.reportID = entry?.id

                self?.endings += 1
            }
        }
    }

    private func drop(_ activity: Activity) {
        activities.removeAll { $0 === activity }
    }
}
