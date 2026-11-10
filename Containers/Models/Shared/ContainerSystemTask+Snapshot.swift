//
//  ContainerSystemTask+Snapshot.swift
//  Containers
//
//  Created by Axel Martinez on 12/09/2026.
//

import ContainersCore
import Foundation

extension ContainerSystemTask {
    nonisolated struct Snapshot: Hashable, Sendable {
        enum Phase: Hashable, Sendable {
            case executing
            case stopped
            case failed(reportID: String?)
        }

        enum Source: Sendable {
            case work(ContainerSystemTask)
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
        init(_ task: ContainerSystemTask) {
            self.id = task.id
            self.title = task.title
            self.subtitle = task.subtitle
            self.source = .work(task)

            if task.error != nil {
                self.phase = .failed(reportID: task.reportID)
            } else if task.isStopped {
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

        static func == (lhs: Snapshot, rhs: Snapshot) -> Bool {
            lhs.id == rhs.id && lhs.title == rhs.title
                && lhs.subtitle == rhs.subtitle && lhs.phase == rhs.phase
                && lhs.source.isSame(as: rhs.source)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(phase)
        }
    }
}

@MainActor
extension ContainerSystemTask.Snapshot {
    var canRetry: Bool {
        guard case .work(let task) = source else { return false }

        return task.canRetry
    }

    var failureTitle: String? {
        switch source {
        case .work(let task): failure(of: task)?.title
        case .report(let report): report.message
        }
    }

    var failureMessage: String? {
        switch source {
        case .work(let task): failure(of: task)?.message
        case .report(let report): report.message
        }
    }

    private func failure(of task: ContainerSystemTask) -> ErrorAlert? {
        task.error.map { ErrorAlert(task.failureTitle, error: $0) }
    }

    /// A failure or a stop always shows, so it can be read or run again.
    var showsProgress: Bool {
        guard isExecuting, case .work(let task) = source else { return true }

        return task.showsProgress
    }

    var step: String { progress?.localizedDescription ?? "" }
    var detail: String { progress?.localizedAdditionalDescription ?? "" }
    var fraction: Double? { progress?.fractionCompleted }

    private var progress: ProgressObserver? {
        guard case .work(let task) = source else { return nil }

        return task.progress
    }
}

extension ContainerSystemTask.Snapshot.Source {
    nonisolated fileprivate func isSame(as other: Self) -> Bool {
        switch (self, other) {
        case (.work(let lhs), .work(let rhs)): lhs === rhs
        case (.report(let lhs), .report(let rhs)): lhs.id == rhs.id
        default: false
        }
    }
}
