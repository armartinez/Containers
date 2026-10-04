//
//  SettingsRow.swift
//  Containers
//
//  Created by Axel Martinez on 09/08/2026.
//

import SwiftUI

/// A row in a settings pane: a heading, the control, and a caption under it.
///
/// Stacked rather than the two columns `FormRow` lays a sheet's fields out in,
/// which is how a settings pane reads.
struct SettingsRow<Content: View>: View {
    var title: String?
    var titleIcon: String?
    var subtitle: String?
    var description: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if title != nil || subtitle != nil {
                header
            }

            content
                .frame(maxWidth: .infinity, alignment: .leading)

            if let description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let title {
                if let titleIcon {
                    Label(title, systemImage: titleIcon)
                        .font(.headline)
                } else {
                    Text(title)
                        .font(.headline)
                }
            }

            Spacer()

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
