//
//  ActivitySnapshot.swift
//  Containers
//
//  Created by Axel Martinez on 12/09/2026.
//

import ContainerSystem
import Foundation

nonisolated struct ActivitySnapshot: Hashable, Sendable {
    enum Phase: Hashable, Sendable {
        case executing
        case stopped
        case failed(reportID: String?)
    }

    enum Source: Sendable {
        case work(ActivityCenter.Activity)
        case report(Report)
    }

    let id: String
    let title: String
    let subtitle: String
    let phase: Phase
    let source: Source

    /// `id` can differ from `report.name`: an image is reported under the
    /// reference asked for, but its row is known by the resolved one.
    init(report: Report, id: String? = nil) {
        self.id = id ?? report.name
        self.title = report.name
        self.subtitle = ""
        self.phase = .failed(reportID: report.id)
        self.source = .report(report)
    }

    @MainActor
    init(_ activity: ActivityCenter.Activity) {
        self.id = activity.id
        self.title = activity.title
        self.subtitle = activity.subtitle
        self.source = .work(activity)

        if activity.error != nil {
            self.phase = .failed(reportID: activity.reportID)
        } else if activity.isStopped {
            self.phase = .stopped
        } else {
            self.phase = .executing
        }
    }

    var isExecuting: Bool { phase == .executing }
    var isStopped: Bool { phase == .stopped }

    var reportID: String? {
        guard case .failed(let reportID) = phase else { return nil }

        return reportID
    }

    var isReported: Bool {
        guard case .report = source else { return false }

        return true
    }

    static func == (lhs: ActivitySnapshot, rhs: ActivitySnapshot) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title
            && lhs.subtitle == rhs.subtitle && lhs.phase == rhs.phase
            && lhs.source.isSame(as: rhs.source)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(phase)
    }
}

@MainActor
extension ActivitySnapshot {
    var canRetry: Bool {
        guard case .work(let activity) = source else { return false }

        return activity.canRetry
    }

    var failureTitle: String? {
        switch source {
        case .work(let activity): failure(of: activity)?.title
        case .report(let report): report.message
        }
    }

    var failureMessage: String? {
        switch source {
        case .work(let activity): failure(of: activity)?.message
        case .report(let report): report.message
        }
    }

    private func failure(of activity: ActivityCenter.Activity) -> ErrorAlert? {
        activity.error.map { ErrorAlert(activity.failureTitle, error: $0) }
    }

    /// A failure or a stop always shows, so it can be read or run again.
    var showsProgress: Bool {
        guard isExecuting, case .work(let activity) = source else { return true }

        return activity.showsProgress
    }

    var step: String { progress?.localizedDescription ?? "" }
    var detail: String { progress?.localizedAdditionalDescription ?? "" }
    var fraction: Double? { progress?.fractionCompleted }

    private var progress: ProgressObserver? {
        guard case .work(let activity) = source else { return nil }

        return activity.progress
    }
}

extension ActivitySnapshot.Source {
    nonisolated fileprivate func isSame(as other: Self) -> Bool {
        switch (self, other) {
        case (.work(let lhs), .work(let rhs)): lhs === rhs
        case (.report(let lhs), .report(let rhs)): lhs.id == rhs.id
        default: false
        }
    }
}
