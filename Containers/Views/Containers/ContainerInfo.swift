//
//  ContainerInfo.swift
//  Containers
//
//  Created by Axel Martinez on 10/2/26.
//

import ContainerSystem
import Containerization
import ContainerizationOCI
import SwiftUI

struct ContainerInfo: View {
    let snapshot: ContainerSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            InfoSection {
                InfoRow(label: "ID", value: snapshot.id)
                InfoRow(
                    label: "Image",
                    value: snapshot.configuration.image.reference
                )
                InfoRow(label: "OS", value: osSummary)
                InfoRow(
                    label: "Arch",
                    value: snapshot.configuration.platform.architecture
                )

                if let commandSummary {
                    InfoRow(label: "Command", value: commandSummary)
                }

                if let startedAtSummary {
                    InfoRow(label: "Last Started", value: startedAtSummary)
                }

                if let portsSummary {
                    InfoRow(label: "Ports", value: portsSummary)
                }

                InfoRow(
                    label: "Root Filesystem",
                    value: snapshot.configuration.readOnly
                        ? "Read-only" : "Read-write"
                )
                InfoRow(
                    label: "Virtualization",
                    value: snapshot.configuration.virtualization
                        ? "Enabled" : "Disabled"
                )
                InfoRow(
                    label: "SSH Agent",
                    value: snapshot.configuration.ssh
                        ? "Forwarded" : "Not forwarded"
                )
            }

            if !snapshot.configuration.labels.isEmpty {
                InfoSection {
                    ForEach(sortedLabels, id: \.key) { label in
                        InfoRow(label: label.key, value: label.value)
                    }
                }
            }
        }
        .padding(20)

    }

    private var sortedLabels: [(key: String, value: String)] {
        snapshot.configuration.labels.sorted {
            $0.key.localizedStandardCompare($1.key) == .orderedAscending
        }
    }

    private var osSummary: String {
        snapshot.configuration.platform.os.localizedCapitalized
    }

    private var commandSummary: String? {
        let process = snapshot.configuration.initProcess
        let executable = process.executable.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let arguments = process.arguments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return ([executable] + arguments)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .nilIfEmpty
    }

    private var portsSummary: String? {
        let ports = snapshot.configuration.publishedPorts.map(\.description)
        let sockets = snapshot.configuration.publishedSockets.map {
            "\($0.hostPath) -> \($0.containerPath)"
        }

        return (ports + sockets).joined(separator: ", ").nilIfEmpty
    }

    private var startedAtSummary: String? {
        guard let startedDate = snapshot.startedDate else {
            return nil
        }

        return Self.relativeFormatter.localizedString(
            for: startedDate,
            relativeTo: Date()
        )
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}

extension String {
    fileprivate var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
