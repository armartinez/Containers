//
//  SearchBar.swift
//  Containers
//
//  Created by Axel Martinez on 26/09/2026.
//

import ContainerSystem
import SwiftUI

/// The reports' searches: all, each kind, and those saved. Sits in the
/// dashboard's titlebar, as Console's does, so it shares the toolbar's glass.
struct SearchBar: View {
    /// What the reports are narrowed by, which the dashboard holds.
    @Binding var filters: [ReportFilter]

    @AppStorage("savedReportSearches") private var savedSearchesData = Data()
    @State private var isSavingSearch = false

    private var savedSearches: [SavedReportSearch] {
        get {
            (try? JSONDecoder().decode([SavedReportSearch].self, from: savedSearchesData)) ?? []
        }
        nonmutating set {
            savedSearchesData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    /// The searches the bar offers, in order: all of the reports, each kind
    /// of work, and those saved.
    private var searches: [[ReportFilter]] {
        [[]] + Report.Kind.allCases.map { [.kind($0)] }
            + savedSearches.map(\.filters)
    }

    /// What is being shown, the way Console says which of its messages are:
    /// the whole of them, one kind at a time, or a search saved by name. A
    /// search that is none of these can be saved as one.
    var body: some View {
        ScopeBar(drawsBackground: false) {
            HStack(spacing: 2) {
                BarToggle("All Reports", selection: $filters, value: [])

                ForEach(Report.Kind.allCases, id: \.self) { kind in
                    BarToggle(kind.title, selection: $filters, value: [.kind(kind)])
                }

                ForEach(savedSearches) { search in
                    BarToggle(search.name, selection: $filters, value: search.filters)
                        .contextMenu {
                            Button("Remove") {
                                savedSearches.removeAll { $0.id == search.id }
                            }
                        }
                }
            }
        } trailing: {
            if !searches.contains(filters) {
                Button("Save") {
                    isSavingSearch = true
                }
                .buttonStyle(OutlinedBarButtonStyle())
            }
        }
        .sheet(isPresented: $isSavingSearch) {
            SaveSearchSheet { name in
                savedSearches.append(
                    SavedReportSearch(name: name, filters: filters)
                )
            }
        }
    }
}

/// A button in the bar that acts on what is shown, drawn as Console draws its
/// Save: outlined and quiet, so that it does not read as another of the
/// choices beside it.
private struct OutlinedBarButtonStyle: ButtonStyle {
    private static let cornerRadius: CGFloat = 4

    func makeBody(configuration: Configuration) -> some View {
        Label(configuration: configuration)
    }

    private struct Label: View {
        let configuration: Configuration

        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(.callout)
                .foregroundStyle(
                    isHovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
                )
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: OutlinedBarButtonStyle.cornerRadius)
                        .fill(
                            configuration.isPressed
                                ? Color(nsColor: .quaternaryLabelColor) : .clear
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OutlinedBarButtonStyle.cornerRadius)
                        .strokeBorder(Color(nsColor: .quinaryLabelColor))
                )
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }
    }
}
