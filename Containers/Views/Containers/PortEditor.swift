//
//  PortEditor.swift
//  Containers
//
//  Created by Axel Martinez on 03/08/2026.
//

import ContainerSystem
import SwiftUI

/// The editors the create sheet's lists open for one drafted item at a time.
struct PortEditor: View {
    /// Refuses a number outside the port range, so one that no port could
    /// take never reaches the mapping.
    private static let portFormatter: NumberFormatter = {
        let formatter = NumberFormatter()

        formatter.allowsFloats = false
        formatter.minimum = PortMapping.range.lowerBound as NSNumber
        formatter.maximum = PortMapping.range.upperBound as NSNumber

        return formatter
    }()

    @Binding var port: PortMapping

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Host Address", text: $port.hostAddress)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                TextField(
                    "Host Port",
                    value: $port.host,
                    formatter: Self.portFormatter
                )
                .textFieldStyle(.roundedBorder)
                TextField(
                    "Container Port",
                    value: $port.container,
                    formatter: Self.portFormatter
                )
                .textFieldStyle(.roundedBorder)
            }

            Picker("Protocol", selection: $port.publishProtocol) {
                Text("TCP").tag(PublishProtocol.tcp)
                Text("UDP").tag(PublishProtocol.udp)
            }
            .pickerStyle(.segmented)
        }
    }
}
