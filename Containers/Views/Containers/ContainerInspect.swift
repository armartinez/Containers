//
//  ContainerInspect.swift
//  Containers
//
//  Created by Axel Martinez on 06/06/2026.
//

import ContainerSystem
import Containerization
import ContainerizationOCI
import Foundation
import SwiftUI

struct ContainerInspect: View {
    let snapshot: ContainerSnapshot

    var body: some View {
        InspectView(value: PrintableContainer(snapshot))
    }
}

private struct PrintableContainer: Encodable {
    let configuration: ContainerConfiguration
    let status: PrintableContainerStatus

    var id: String {
        configuration.id
    }

    init(_ container: ContainerSnapshot) {
        self.configuration = container.configuration
        self.status = PrintableContainerStatus(
            state: container.status,
            networks: container.networks,
            startedDate: container.startedDate
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case configuration
        case status
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(configuration, forKey: .configuration)
        try container.encode(status, forKey: .status)
    }
}

private struct PrintableContainerStatus: Encodable {
    let state: ContainerStatus
    let networks: [Attachment]
    let startedDate: Date?
}

#Preview {
    ContainerInspect(
        snapshot: ContainerSnapshot(
            configuration: ContainerConfiguration(
                id: "preview-container",
                image: ImageDescription(
                    reference: "nginx:latest",
                    descriptor: ContainerizationOCI.Descriptor(
                        mediaType: "application/vnd.oci.image.manifest.v1+json",
                        digest: "sha256:1234567890abcdef",
                        size: 1024
                    )
                ),
                process: ProcessConfiguration(
                    executable: "/bin/sh",
                    arguments: [],
                    environment: ["PATH=/usr/bin"],
                    workingDirectory: "/",
                    terminal: false
                )
            ),
            status: .running,
            networks: [],
            startedDate: Date()
        )
    )
    .frame(width: 550, height: 420)
}
