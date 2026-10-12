//
//  MountEditor.swift
//  Containers
//
//  Created by Axel Martinez on 04/08/2026.
//

import SwiftUI

struct MountEditor: View {
    @Binding var mount: Mount

    private var isTemporary: Binding<Bool> {
        Binding {
            mount.isTemporary
        } set: { isTemporary in
            mount.isTemporary = isTemporary
            if isTemporary { mount.hostURL = nil }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Temporary mount", isOn: isTemporary)
                .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 4) {
                Text("Source")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                FileSelection(
                    placeholder: "No source selected",
                    fileURL: $mount.hostURL,
                    canChooseDirectories: true,
                    label: .path,
                    recents: .mountSource
                )
                .disabled(mount.isTemporary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Target (Required)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                FormField(
                    placeholder: "/workspace",
                    value: $mount.containerPath
                )
            }
        }
    }
}
