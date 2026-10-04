//
//  ReportDetailWindow.swift
//  Containers
//
//  Created by Axel Martinez on 16/09/2026.
//

import ContainerSystem
import SwiftUI

struct ReportDetailWindow: View {
    let id: String

    @Environment(ReportManager.self) private var reportManager

    @State private var entry: Report?
    @State private var text = ""
    @State private var search = ""
    @State private var toolbar = ReportToolbarController()

    /// The lines that mention what is searched for, which is how Console narrows a file down to its matches.
    private var shown: String {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else { return text }

        return
            text
            .components(separatedBy: .newlines)
            .filter { $0.localizedCaseInsensitiveContains(query) }
            .joined(separator: "\n")
    }

    var body: some View {
        ScrollView {
            Text(shown)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
        }
        .defaultScrollAnchor(.top)
        .background(Color(nsColor: .textBackgroundColor))
        .navigationTitle(entry?.name ?? "")
        .background(
            ReportToolbarBinder(
                controller: toolbar,
                onSearch: { search = $0 }
            )
        )
        .task {
            await load()
        }
    }

    private func load() async {
        entry = await reportManager.entry(for: id)
        text = await reportManager.body(of: id) ?? ""

        await reportManager.markRead([id])
    }
}
