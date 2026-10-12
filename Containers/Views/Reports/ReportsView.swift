//
//  ReportsView.swift
//  Containers
//
//  Created by Axel Martinez on 16/09/2026.
//

import ContainerSystem
import SwiftUI

/// Reports of failed work, added automatically as work fails.
struct ReportsView: View {
    @Environment(ReportManager.self) private var reportManager
    @Environment(ActivityCenter.self) private var activityCenter
    @Environment(\.openWindow) private var openWindow

    @Binding var searchText: String
    @Binding var selection: Set<Report.ID>
    @Binding var actions: SelectionActions
    @Binding var command: SelectionCommand?

    /// Shown as tokens in the dashboard's search field.
    @Binding var filters: [ReportFilter]

    var refreshTrigger: Int

    @State private var reading: Task<Void, Never>?

    /// How long a report stays selected before it counts as read, as in Mail.
    private static let readingTime: Duration = .seconds(2)

    private var trimmedText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Typed text searches every field until Return makes it a token.
    private var filteredReports: [Report] {
        let typed =
            trimmedText.isEmpty
            ? [] : [ReportFilter(field: .any, value: trimmedText)]

        return reportManager.reports.filter { report in
            (filters + typed).allSatisfy { $0.matches(report) }
        }
    }

    private var rowActions: TableRowActions<Report> {
        TableRowActions(
            noun: "Report",
            name: \.name,
            open: open,
            delete: delete
        )
    }

    var body: some View {
        table
    }

    private var table: some View {
        TableView(
            rows: filteredReports,
            selection: $selection,
            // Newest first, as Console opens on the most recent it keeps.
            sortOrder: [KeyPathComparator(\.date, order: .reverse)],
            actions: $actions,
            command: $command,
            rowActions: rowActions,
            refreshTrigger: refreshTrigger,
            onClear: {},
            onRefresh: reportManager.refresh,
            menu: { selected in
                Button("Reveal in Finder", systemImage: "folder") {
                    reveal(selected)
                }
            }
        ) {
            TableColumn("Type", value: \.level.title) { report in
                Image(
                    systemName: report.symbol
                )
                .rowTint(report.color)
                .frame(maxWidth: .infinity)
                .help(report.level.title)
                .accessibilityLabel(
                    report.isRead
                        ? report.level.title
                        : "\(report.level.title), unread"
                )
            }
            .width(40)

            TableColumn("Date", value: \.date) { report in
                Text(report.dateText)
                    .fontWeight(report.isRead ? .regular : .semibold)
                    .lineLimit(1)
            }
            .width(min: 140, ideal: 180, max: 220)

            TableColumn("Kind", value: \.kind.title) { report in
                Text(report.kind.title)
                    .fontWeight(report.isRead ? .regular : .semibold)
                    .lineLimit(1)
            }
            .width(min: 60, ideal: 80, max: 110)

            TableColumn("Name", value: \.name) { report in
                Text(report.name)
                    .fontWeight(report.isRead ? .regular : .semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .width(min: 140, ideal: 200)

            TableColumn("Message", value: \.message) { report in
                Text(report.message)
                    .fontWeight(report.isRead ? .regular : .semibold)
                    .lineLimit(1)
            }
            .width(min: 160, ideal: 240)
        }
        .onChange(of: selection) { _, _ in
            readSelected()
        }
        .onDisappear {
            reading?.cancel()
        }
    }

    private func open(_ entry: Report) {
        openWindow.report(entry.id)
    }

    /// Only once selected long enough to be looked at, not passed over.
    private func readSelected() {
        reading?.cancel()

        let selected = Array(selection)

        guard !selected.isEmpty else { return }

        reading = Task {
            try? await Task.sleep(for: Self.readingTime)

            guard !Task.isCancelled else { return }

            await reportManager.markRead(selected)
        }
    }

    private func delete(_ entries: [Report]) {
        guard !entries.isEmpty else { return }

        let ids = entries.map(\.id)

        Task {
            await reportManager.remove(ids)
            activityCenter.forgetFailures(reportedAs: Set(ids))
            selection.subtract(ids)
        }
    }

    private func reveal(_ entries: [Report]) {
        let urls = entries.compactMap { reportManager.url(for: $0.id) }

        guard !urls.isEmpty else { return }

        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}
