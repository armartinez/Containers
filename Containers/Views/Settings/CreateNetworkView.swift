//
//  CreateNetworkView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/10/31.
//

import ContainersCore
import SwiftUI

struct CreateNetworkView: View {
    @Environment(NetworkManager.self) private var networkManager
    @Environment(\.dismiss) private var dismiss

    /// Called once the network is made.
    var onCreate: () -> Void = {}

    @SwiftUI.State private var name = ""
    @SwiftUI.State private var mode: NetworkMode = .nat
    @SwiftUI.State private var subnet = ""
    @SwiftUI.State private var errorAlert: ErrorAlert?
    @SwiftUI.State private var isCreating = false

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        CreateView(
            title: "Create New Network",
            error: $errorAlert,
            isProcessing: isCreating,
            progressTitle: "Creating network…",
            width: 550,
            height: 330,
            content: {
                FormStack {
                    FormRow(
                        title: "Name",
                        description:
                            "Names use lowercase letters, numbers, periods, underscores, and hyphens, and start and end with a letter or number."
                    ) {
                        FormField(placeholder: "Ex: backend", value: $name, filter: { $0.lowercased() })
                    }

                    FormRow(
                        title: "Mode",
                        description: mode == .nat
                            ? "Containers reach other networks and the internet through your Mac."
                            : "Containers reach only each other and your Mac."
                    ) {
                        FormPicker(
                            placeholder: "Mode",
                            options: NetworkMode.allCases,
                            selection: $mode,
                            title: { $0 == .nat ? "NAT" : "Host Only" }
                        )
                    }

                    FormRow(
                        title: "Subnet",
                        description: "Leave empty for one picked automatically."
                    ) {
                        FormField(placeholder: "Ex: 192.168.100.0/24", value: $subnet)
                    }
                }
            },
            actions: {
                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .frame(minWidth: .sheetButtonLabelWidth)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                Button {
                    create()
                } label: {
                    Text("Create")
                        .frame(minWidth: .sheetButtonLabelWidth)
                }
                .defaultAction(enabled: !isCreating && NetworkConfiguration.isValidName(trimmedName))
            }
        )
    }

    private func create() {
        let subnet = subnet.trimmingCharacters(in: .whitespacesAndNewlines)

        isCreating = true

        Task {
            do {
                try await networkManager.createNetwork(name: trimmedName, mode: mode, subnet: subnet.isEmpty ? nil : subnet)
                onCreate()
                dismiss()
            } catch {
                errorAlert = ErrorAlert("The network couldn’t be created.", error: error, showsDetails: false)
            }

            isCreating = false
        }
    }
}

extension NetworkMode: @retroactive CustomStringConvertible {
    public var description: String {
        rawValue
    }
}
