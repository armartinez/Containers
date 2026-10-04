//
//  InfoRow.swift
//  Containers
//
//  Created by Axel Martinez on 20/5/26.
//

import SwiftUI

struct InfoRow: View {
    let icon: String?
    let label: String?
    let value: String
    let action: ActionButton?

    /// The label column's width, which is also where the value starts — widen
    /// it to move the pair right, narrow it to move it left.
    private static let labelWidth: CGFloat = 200
    private static let labelTopPadding: CGFloat = 5

    init(
        icon: String? = nil,
        label: String? = nil,
        value: String,
        action: ActionButton? = nil
    ) {
        self.icon = icon
        self.label = label
        self.value = value
        self.action = action
    }

    var body: some View {
        HStack(alignment: .top) {
            if let icon, let label {
                Label(
                    "\(label):",
                    systemImage: icon
                )
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(
                    width: Self.labelWidth,
                    alignment: .trailing
                )
                .padding(.top, Self.labelTopPadding)
            } else if let icon {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(
                        width: Self.labelWidth,
                        alignment: .trailing
                    )
                    .padding(.top, Self.labelTopPadding)
            } else if let label {
                Text("\(label):")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(
                        width: Self.labelWidth,
                        alignment: .trailing
                    )
                    .padding(.top, Self.labelTopPadding)
            } else {
                Spacer()
                    .frame(width: Self.labelWidth)
                    .padding(.top, Self.labelTopPadding)
            }

            HStack(alignment: .center, spacing: 8) {
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let action {
                    action
                }
            }
            .padding(.vertical, 4)
            .frame(minHeight: 22)
        }
        .padding(.horizontal, 12)
    }
}
