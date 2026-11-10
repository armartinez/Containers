//
//  SettingsList.swift
//  Containers
//
//  Created by Axel Martinez on 2026/10/31.
//

import SwiftUI

/// A list of selectable rows in a settings pane, with a bar of actions under them.
struct SettingsList<Item: Identifiable, Row: View, Footer: View>: View {
    var items: [Item]
    var emptyMessage: String
    @Binding var selection: Item.ID?
    @ViewBuilder var row: (Item) -> Row
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        // A selected row's highlight is its own separator.
                        if index > 0 {
                            Divider()
                                .padding(.horizontal, 12)
                                .opacity(isSelected(item) || isSelected(items[index - 1]) ? 0 : 1)
                        }

                        rowView(for: item)
                    }
                }
            }

            Divider()

            HStack(spacing: 0) {
                footer
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 24)

                Spacer()
            }
            .padding(.horizontal, 4)
            .background(Color(nsColor: .quaternarySystemFill), in: Rectangle())
        }
        .background(Color(nsColor: .quaternarySystemFill), in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func isSelected(_ item: Item) -> Bool {
        selection == item.id
    }

    private func rowView(for item: Item) -> some View {
        let isSelected = isSelected(item)

        return row(item)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(isSelected ? Color.accentColor : .clear, in: Rectangle())
            .contentShape(Rectangle())
            .onTapGesture {
                selection = isSelected ? nil : item.id
            }
    }
}

private struct PreviewItem: Identifiable {
    var id: String { name }
    var name: String
}

#Preview {
    @Previewable @State var selection: String? = "test"

    VStack(spacing: 20) {
        SettingsList(
            items: ["test", "dev.local", "internal.example.com"].map(PreviewItem.init(name:)),
            emptyMessage: "No DNS Domains",
            selection: $selection
        ) { item in
            Text(item.name)
        } footer: {
            Button("Use as Default", systemImage: "star") {}
        }

        SettingsList(items: [PreviewItem](), emptyMessage: "No DNS Domains", selection: $selection) { item in
            Text(item.name)
        } footer: {
            Button("Use as Default", systemImage: "star") {}
                .disabled(true)
        }
    }
    .padding(24)
    .frame(width: 520)
}
