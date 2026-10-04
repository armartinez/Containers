//
//  VolumeEditor.swift
//  Containers
//
//  Created by Axel Martinez on 03/08/2026.
//

import ContainerSystem
import SwiftUI

struct VolumeEditor: View {
    @Binding var mount: VolumeMount
    let availableVolumes: [Volume]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Anonymous volume", isOn: isAnonymous)
                .toggleStyle(.checkbox)

            if mount.source == .volume {
                field("Volume") {
                    FormPicker(
                        placeholder: "Select a volume...",
                        options: availableVolumes.map(\.name),
                        selection: $mount.volumeName
                    )
                }
            }

            field("Target (Required)") {
                FormField(placeholder: "/data", value: $mount.target)
            }
        }
    }

    private var isAnonymous: Binding<Bool> {
        Binding(
            get: { mount.source == .anonymousVolume },
            set: { anonymous in
                mount.source = anonymous ? .anonymousVolume : .volume
                if anonymous { mount.volumeName = "" }
            }
        )
    }

    private func field<Content: View>(
        _ caption: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)

            content()
        }
    }
}
