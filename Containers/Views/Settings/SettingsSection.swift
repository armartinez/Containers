//
//  SettingsSection.swift
//  Containers
//
//  Created by Axel Martinez on 2026/06/06.
//

import SwiftUI

struct SettingsSection<Content: View>: View {
    var title: String?
    var description: String?
    @ViewBuilder var content: Content

    var body: some View {
        GroupBox {
            Group(subviews: content) { rows in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows.indices, id: \.self) { index in
                        rows[index]

                        if index < rows.index(before: rows.endIndex) {
                            Divider()
                                .padding(.vertical, 12)
                        }
                    }
                }
            }
            .padding(12)
        } label: {
            if title != nil || description != nil {
                VStack(alignment: .leading, spacing: 3) {
                    if let title {
                        Text(title)
                            .font(.headline)
                            .fontWeight(.semibold)
                    }

                    if let description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 5)
            }
        }
    }
}
