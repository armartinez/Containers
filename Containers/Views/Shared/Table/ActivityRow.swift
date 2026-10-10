//
//  ActivityRow.swift
//  Containers
//
//  Created by Axel Martinez on 08/10/2026.
//

import SwiftUI

/// A table row that work can be under way on.
nonisolated protocol ActivityRow: Identifiable where ID == String {
    var name: String { get }
    var activity: ActivitySnapshot? { get set }
    /// Whether the row only stands in for work, rather than for something that exists.
    var isPending: Bool { get }
}

extension ActivityRow {
    var isPending: Bool { false }

    /// Whether an action is under way on the row.
    var isExecuting: Bool {
        activity?.isExecuting == true
    }

    /// Nothing can be done with a row while an action executes on it. One
    /// whose last action failed can be acted on, so it can be tried again.
    var isDisabled: Bool {
        isPending || isExecuting
    }

    /// The work the row only stands in for, whose own menu it gets instead.
    var pendingWork: ActivitySnapshot? {
        isPending ? activity : nil
    }
}

extension View {
    /// Shows a cell's content as secondary while nothing can be done with its
    /// row, or while `isDimmed` holds.
    func rowForeground(for row: some ActivityRow, isDimmed: Bool = false) -> some View {
        foregroundStyle(row.isDisabled || isDimmed ? .secondary : .primary)
    }
}

/// A row's name, followed by the mark of the work under way on it.
struct ActivityRowName<Row: ActivityRow>: View {
    let row: Row
    /// Passed in, as the mark's is: AppKit can update a cell after its row is gone, with no environment left.
    let activityCenter: ActivityCenter
    let openReport: (String) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(row.name)
                .lineLimit(1)
                .rowForeground(for: row)

            if let activity = row.activity, activity.showsProgress {
                Spacer(minLength: 0)

                RowProgressIndicator(
                    activity: activity,
                    activityCenter: activityCenter,
                    openReport: openReport
                )
            }
        }
    }
}

extension ContainerItem: ActivityRow {}

extension ImageItem: ActivityRow {}

extension VolumeItem: ActivityRow {}
