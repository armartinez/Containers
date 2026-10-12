//
//  RowProgressIndicator.swift
//  Containers
//
//  Created by Axel Martinez on 14/09/2026.
//

import ContainerSystem
import SwiftUI

/// A row's activity mark: a filling pie, a failure mark, or a retry button once stopped.
struct RowProgressIndicator: View {
    /// Glyphs are sized to it, since a font size draws them larger than the pie.
    private static let markSize: CGFloat = 16

    /// Centres every mark alike, however wide its glyph draws.
    private static let slot: CGFloat = 18

    let activity: ActivitySnapshot
    /// Passed in: AppKit can update a cell after its row is gone, with no environment left.
    let activityCenter: ActivityCenter
    let openReport: (String) -> Void

    @State private var isShowingDetails = false
    @State private var isHovering = false

    private static let failureSymbol = "xmark.octagon.fill"

    var body: some View {
        Group {
            if activity.isStopped, activity.canRetry {
                Button {
                    activityCenter.retry(activity.id)
                } label: {
                    Image(systemName: "arrow.clockwise.circle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: Self.markSize, height: Self.markSize)
                        .foregroundStyle(.secondary)
                        .frame(width: Self.slot, height: Self.slot)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Retry")
            } else {
                Button {
                    isShowingDetails.toggle()
                } label: {
                    mark
                        .frame(width: Self.slot, height: Self.slot)
                        .contentShape(Rectangle())
                        .onHover { isHovering = $0 }
                }
                .buttonStyle(.plain)
                .help(helpText)
                .popover(isPresented: $isShowingDetails, arrowEdge: .bottom) {
                    ActivityDetails(
                        activity: activity,
                        onStop: { activityCenter.stop(activity.id) },
                        onRetry: { activityCenter.retry(activity.id) },
                        onOpenReport: { reportID in
                            isShowingDetails = false
                            openReport(reportID)
                        }
                    )
                }
            }
        }
        // Stopping swaps the mark for the retry button; the popover mustn't
        // reappear on its own when the work runs again.
        .onChange(of: activity.isStopped) { _, _ in
            isShowingDetails = false
        }
    }

    @ViewBuilder
    private var mark: some View {
        if activity.failureMessage != nil {
            Image(systemName: isHovering ? "info.circle" : Self.failureSymbol)
                .resizable()
                .scaledToFit()
                .frame(width: Self.markSize, height: Self.markSize)
                .foregroundStyle(.secondary)
        } else if activity.isStopped {
            Image(systemName: "stop.circle")
                .resizable()
                .scaledToFit()
                .frame(width: Self.markSize, height: Self.markSize)
                .foregroundStyle(.secondary)
        } else if isHovering {
            Image(systemName: "info.circle")
                .resizable()
                .scaledToFit()
                .frame(width: Self.markSize, height: Self.markSize)
                .rowTint(.blue)
        } else {
            // In the foreground colour, so a selected row turns it white.
            ZStack {
                Circle()
                    .strokeBorder(.foreground, lineWidth: 1)

                PieSlice(fraction: activity.fraction ?? 0)
                    .fill(.foreground)
                    .animation(.easeOut(duration: 0.25), value: activity.fraction)
            }
            .frame(width: Self.markSize, height: Self.markSize)
            .rowTint(.blue)
        }
    }

    private var helpText: String {
        if activity.failureMessage != nil { return "Show Error" }
        if activity.isStopped { return "Stopped" }
        return "Show Progress"
    }
}

/// Stop, Retry and Delete for rows that stand for work.
struct ActivityMenuItems: View {
    let work: [ActivitySnapshot]
    /// Not read from the environment, for the same reason as the mark's.
    let activityCenter: ActivityCenter
    let reportManager: ReportManager

    var body: some View {
        let running = work.filter(\.isExecuting)
        let ended = work.filter { !$0.isExecuting }
        let retryable = ended.filter(\.canRetry)
        // Deleting a mark read back from a report deletes the report.
        let reported = ended.filter(\.isReported).compactMap(\.reportID)

        if !running.isEmpty {
            Button("Stop", systemImage: "stop") {
                for activity in running { activityCenter.stop(activity.id) }
            }
        }

        if !retryable.isEmpty {
            Button("Retry", systemImage: "arrow.clockwise") {
                for activity in retryable { activityCenter.retry(activity.id) }
            }
        }

        if !ended.isEmpty {
            if !running.isEmpty || !retryable.isEmpty {
                Divider()
            }

            Button(
                reported.isEmpty ? "Delete" : "Delete Report",
                systemImage: "trash",
                role: .destructive
            ) {
                for activity in ended { activityCenter.remove(activity.id) }

                Task { await reportManager.remove(reported) }
            }
        }
    }
}

private struct ActivityDetails: View {
    let activity: ActivitySnapshot
    let onStop: () -> Void
    let onRetry: () -> Void
    let onOpenReport: (String) -> Void

    /// Shown in the detail line, since a tooltip needs a wait.
    @State private var hovered: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The popover inherits the cell's one-line limit.
            Text(heading)
                .font(.subheadline)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                // Takes the slack, so the buttons stay put.
                account
                    .frame(maxWidth: .infinity, alignment: .leading)

                if activity.isExecuting {
                    button("xmark.circle.fill", "Stop the work", action: onStop)
                } else if activity.canRetry {
                    button("arrow.clockwise.circle.fill", "Run it again", action: onRetry)
                }

                if let reportID = activity.reportID {
                    button("arrow.up.forward.circle", "Show the report of what happened") {
                        onOpenReport(reportID)
                    }
                }
            }

            if activity.isExecuting {
                Text(hovered ?? activity.detail)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(width: 340)
        // The pointer can leave the popover without a button seeing it go.
        .onContinuousHover { phase in
            if case .ended = phase { hovered = nil }
        }
        .onDisappear { hovered = nil }
    }

    @ViewBuilder
    private var account: some View {
        if let failureMessage = activity.failureMessage {
            Text(hovered ?? failureMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if activity.isStopped {
            Text(hovered ?? "Stopped")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            // Linear for both, or unmeasured work draws a spinner.
            Group {
                if let fraction = activity.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
            }
            .progressViewStyle(.linear)
        }
    }

    private func button(
        _ symbol: String,
        _ describing: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        // `onHover` can miss the pointer leaving, which leaves the line stale.
        .onContinuousHover { phase in
            switch phase {
            case .active:
                hovered = describing
            case .ended:
                if hovered == describing { hovered = nil }
            }
        }
    }

    private var heading: String {
        if activity.failureMessage != nil {
            return activity.failureTitle ?? "Something went wrong"
        }

        if activity.isStopped {
            return "Stopped"
        }

        return activity.step.isEmpty ? "Starting…" : activity.step
    }
}

nonisolated private struct PieSlice: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()

        path.move(to: center)
        path.addArc(
            center: center,
            radius: min(rect.width, rect.height) / 2,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * min(max(fraction, 0), 1)),
            clockwise: false
        )
        path.closeSubpath()

        return path
    }
}
