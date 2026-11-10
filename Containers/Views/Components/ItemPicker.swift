//
//  ItemPicker.swift
//  Containers
//
//  Created by Axel Martinez on 2026/07/18.
//

import SwiftUI

struct Item: Identifiable {
    let id: String
    let label: String
}

struct ItemPicker: View {
    let title: String
    let actionTitle: String
    let items: [Item]
    let onSelect: (Item) -> Void

    @State private var searchText = ""
    @State private var selectedID: String?

    @Environment(\.dismiss) private var dismiss

    private var filteredItems: [Item] {
        let sorted = items.sorted { $0.label < $1.label }
        guard
            !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return sorted
        }
        return sorted.filter {
            $0.label.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            FilterField(text: $searchText)
            listArea
            footer
        }
        .padding(20)
        .frame(width: 440, height: 416)
    }

    private var listArea: some View {
        Group {
            if filteredItems.isEmpty {
                Text("No results")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredItems, selection: $selectedID) { item in
                    Text(item.label)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .listRowSeparator(.hidden)
                        .listRowInsets(
                            .init(top: 2, leading: 6, bottom: 2, trailing: 6)
                        )
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(
            Rectangle()
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)

            actionButton
        }
        .controlSize(.regular)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var actionButton: some View {
        Button(actionTitle, action: chooseSelectedItem)
            .defaultAction(enabled: selectedID != nil)
    }

    private func chooseSelectedItem() {
        guard let id = selectedID,
            let item = filteredItems.first(where: { $0.id == id })
        else { return }

        onSelect(item)
        dismiss()
    }
}
