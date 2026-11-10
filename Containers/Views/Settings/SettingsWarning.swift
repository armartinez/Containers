//
//  SettingsWarning.swift
//  Containers
//
//  Created by Axel Martinez on 2026/11/10.
//

import SwiftUI

struct SettingsWarning: View {
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        _ message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Spacer(minLength: 8)

                Button(actionTitle, action: action)
                    .controlSize(.small)
                    .fixedSize()
            }
        }
    }
}
