//
//  ReportSearch.swift
//  Containers
//
//  Created by Axel Martinez on 25/09/2026.
//

import ContainerSystem
import Foundation

/// A search kept under a name, which the bar over the reports offers beside
/// the kinds of work.
struct SavedReportSearch: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    let name: String
    let filters: [ReportFilter]
}

/// One thing a search of the reports is narrowed by, which the search field
/// carries as a token: a part of the report, how it is to compare, and with
/// what.
struct ReportFilter: Codable, Hashable, Sendable {
    var field: Field
    var match: Match = .contains
    let value: String

    /// Which part of a report is looked at, after the table's columns.
    enum Field: String, Codable, CaseIterable, Sendable {
        case any
        case type
        case date
        case kind
        case name
        case message

        var title: String {
            switch self {
            case .any: "Any"
            case .type: "Type"
            case .date: "Date"
            case .kind: "Kind"
            case .name: "Name"
            case .message: "Message"
            }
        }

        /// What of the report is compared, as the table shows it.
        func texts(of report: Report) -> [String] {
            switch self {
            case .any:
                [Field.type, .date, .kind, .name, .message].flatMap {
                    $0.texts(of: report)
                }
            case .type: [report.level.title]
            case .date: [report.dateText]
            case .kind: [report.kind.title]
            case .name: [report.name]
            case .message: [report.message]
            }
        }
    }

    /// How what is looked at has to compare, as Console asks it.
    enum Match: String, Codable, CaseIterable, Sendable {
        case contains
        case doesNotContain
        case equals
        case doesNotEqual

        var title: String {
            switch self {
            case .contains: "Contains"
            case .doesNotContain: "Does Not Contain"
            case .equals: "Equals"
            case .doesNotEqual: "Does Not Equal"
            }
        }

        /// What the token says after the field, where it says anything: the
        /// usual way goes without saying.
        var tokenTitle: String? {
            switch self {
            case .contains: nil
            case .doesNotContain: "Not"
            case .equals: "Is"
            case .doesNotEqual: "Is Not"
            }
        }
    }

    func matches(_ report: Report) -> Bool {
        let texts = field.texts(of: report)

        switch match {
        case .contains:
            return texts.contains { $0.localizedCaseInsensitiveContains(value) }
        case .doesNotContain:
            return !texts.contains { $0.localizedCaseInsensitiveContains(value) }
        case .equals:
            return texts.contains(where: equalsValue)
        case .doesNotEqual:
            return !texts.contains(where: equalsValue)
        }
    }

    /// The kind of work a tab of the bar stands for, compared the usual way,
    /// as Console's own tabs are: no kind's name holds another's.
    static func kind(_ kind: Report.Kind) -> ReportFilter {
        ReportFilter(field: .kind, value: kind.title)
    }

    /// The one thing a window is about, compared the whole way: another's
    /// name may hold this one's, and a window asking for its own reports is
    /// asking for exactly those.
    static func name(_ name: String) -> ReportFilter {
        ReportFilter(field: .name, match: .equals, value: name)
    }

    private func equalsValue(_ text: String) -> Bool {
        text.localizedCaseInsensitiveCompare(value) == .orderedSame
    }
}

extension ReportFilter {
    /// How the search field shows the filter, and what its menu offers: the
    /// part of the report, then the way of comparing.
    var token: SearchToken {
        SearchToken(
            category: [field.title, match.tokenTitle]
                .compactMap { $0 }
                .joined(separator: " "),
            value: value,
            menu: [
                Field.allCases.map {
                    SearchToken.Choice(title: $0.title, isOn: $0 == field)
                },
                Match.allCases.map {
                    SearchToken.Choice(title: $0.title, isOn: $0 == match)
                },
            ]
        )
    }

    /// The filter with a choice from its menu made, told apart by title:
    /// none of the parts of a report is called what a way of comparing is.
    func choosing(_ title: String) -> ReportFilter {
        var filter = self

        if let field = Field.allCases.first(where: { $0.title == title }) {
            filter.field = field
        } else if let match = Match.allCases.first(where: { $0.title == title }) {
            filter.match = match
        }

        return filter
    }
}
