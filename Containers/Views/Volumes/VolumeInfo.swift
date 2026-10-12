//
//  VolumeInfo.swift
//  Containers
//
//  Created by Axel Martinez on 2026/06/07.
//

import ContainerSystem
import SwiftUI

struct VolumeInfo: View {
    let volume: VolumeItem

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            InfoSection {
                InfoRow(label: "Name", value: volume.name)
                InfoRow(label: "Type", value: volume.volumeType.rawValue)
                InfoRow(
                    label: "State",
                    value: volume.isInUse ? "In use" : "Unused"
                )

                if let formattedSize = volume.formattedSize {
                    InfoRow(label: "Size", value: formattedSize)
                }

                InfoRow(label: "Created", value: volume.formattedCreated)
                InfoRow(label: "Driver", value: volume.driver)
                InfoRow(label: "Format", value: volume.format)
            }

            if !volume.labels.isEmpty {
                InfoSection {
                    ForEach(sorted(volume.labels), id: \.key) { label in
                        InfoRow(label: label.key, value: label.value)
                    }
                }
            }

            if !volume.options.isEmpty {
                InfoSection {
                    ForEach(sorted(volume.options), id: \.key) { option in
                        InfoRow(label: option.key, value: option.value)
                    }
                }
            }
        }
        .padding(20)
    }

    private func sorted(
        _ values: [String: String]
    ) -> [(key: String, value: String)] {
        values.sorted {
            $0.key.localizedStandardCompare($1.key) == .orderedAscending
        }
    }
}
