//
//  SaveSearchSheet.swift
//  Containers
//
//  Created by Axel Martinez on 25/09/2026.
//

import SwiftUI

/// Asks what to call a search being saved, as Console asks: one field, and nothing to save until it has a name.
struct SaveSearchSheet: View {
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @FocusState private var isNaming: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 16) {
            HStack {
                Text("Save Search As:")

                // Named by the words beside it, which are what a placeholder
                // would only repeat.
                TextField("", text: $name)
                    .accessibilityLabel("Save Search As")
                    .focused($isNaming)
                    .frame(width: 300)
            }

            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    onSave(trimmedName)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .onAppear { isNaming = true }
    }
}
