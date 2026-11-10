//
//  NetworksSection.swift
//  Containers
//
//  Created by Axel Martinez on 2026/10/31.
//

import ContainerizationExtras
import ContainersCore
import SwiftUI

/// The networks containers attach to, kept in the system's folder, where the container CLI sees them too.
struct NetworksSection: View {
    @Environment(NetworkManager.self) private var networkManager
    @Environment(ContainerSystem.self) private var containerSystem

    @State private var networks: [NetworkConfiguration] = []
    @State private var isCreating = false
    @State private var errorAlert: ErrorAlert?

    /// Beside the CLI's running API server, its networks are its own to change.
    private var canChange: Bool {
        containerSystem.isRunning && !containerSystem.isReadOnly
    }

    var body: some View {
        SettingsSection {
            NetworksHeader {
                Button("Create Network…") {
                    isCreating = true
                }
                .disabled(!canChange)
            }

            if !containerSystem.isRunning {
                Text("Start the container system to see its networks.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(networks) { network in
                    NetworkRow(network: network, canDelete: canChange) {
                        delete(network)
                    }
                }
            }
        }
        .task(id: containerSystem.status, reload)
        .sheet(isPresented: $isCreating) {
            CreateNetworkView {
                Task { await reload() }
            }
        }
        .errorAlert($errorAlert)
    }

    private func reload() async {
        guard containerSystem.isRunning else {
            networks = []
            return
        }

        networks = (try? await networkManager.networks()) ?? []
    }

    private func delete(_ network: NetworkConfiguration) {
        Task {
            do {
                try await networkManager.deleteNetwork(named: network.name)
                await reload()
            } catch {
                errorAlert = ErrorAlert("The network couldn’t be deleted.", error: error)
            }
        }
    }
}

private struct NetworksHeader<Accessory: View>: View {
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Networks")

                Text("New containers join the checked network unless you choose another. The container CLI uses these networks too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            accessory
        }
    }
}

/// A network laid out as System Settings lists Wi-Fi networks: a check beside the one in use, the name, its details
/// and a menu of what can be done with it.
private struct NetworkRow: View {
    let network: NetworkConfiguration
    let canDelete: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .fontWeight(.semibold)
                .opacity(network.name == NetworkConfiguration.defaultName ? 1 : 0)
                .accessibilityHidden(network.name != NetworkConfiguration.defaultName)

            Text(network.name)

            Spacer(minLength: 12)

            Text(network.ipv4Subnet?.description ?? "Automatic")
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Image(systemName: network.mode == .nat ? "globe" : "desktopcomputer")
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .help(network.mode == .nat ? "Reaches the internet through your Mac" : "Reaches only your Mac and its containers")

            Menu {
                Button("Delete Network", role: .destructive, action: onDelete)
                    .disabled(network.isBuiltin || !canDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Network options")
        }
    }
}

#Preview {
    let networks = [
        try? NetworkConfiguration(name: "default"),
        try? NetworkConfiguration(name: "backend", ipv4Subnet: try? CIDRv4("192.168.100.0/24")),
        try? NetworkConfiguration(name: "isolated", mode: .hostOnly),
    ]
    .compactMap { $0 }

    SettingsSection {
        NetworksHeader {
            Button("Create Network…") {}
        }

        ForEach(networks) { network in
            NetworkRow(network: network, canDelete: true) {}
        }
    }
    .padding(24)
    .frame(width: 560)
}
