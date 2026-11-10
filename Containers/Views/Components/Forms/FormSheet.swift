//
//  FormSheet.swift
//  Containers
//
//  Created by Axel Martinez on 27/06/2026.
//

import SwiftUI

struct FormSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss

    var title: String
    var description: String? = nil
    var primaryButtonTitle: String = "Done"
    var showsCancelButton: Bool = false
    var isPrimaryButtonDisabled: Bool = false
    var onSave: (() -> Void)?

    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                if let description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            content

            HStack {
                Spacer()
                if showsCancelButton {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                Button(primaryButtonTitle) {
                    onSave?()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isPrimaryButtonDisabled)
            }
        }
        .padding(20)
        .frame(width: 420, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
