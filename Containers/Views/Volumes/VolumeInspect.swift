//
//  VolumeInspect.swift
//  Containers
//
//  Created by Axel Martinez on 2026/06/07.
//

import ContainerSystem
import SwiftUI

struct VolumeInspect: View {
    let volume: VolumeItem

    var body: some View {
        InspectView(value: PrintableVolume(volume.volume))
    }
}

private struct PrintableVolume: Encodable {
    let configuration: PrintableVolumeConfiguration

    var id: String {
        configuration.name
    }

    init(_ volume: Volume) {
        self.configuration = PrintableVolumeConfiguration(volume)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case configuration
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(configuration, forKey: .configuration)
    }
}

private struct PrintableVolumeConfiguration: Encodable {
    let name: String
    let driver: String
    let format: String
    let source: String
    let creationDate: Date
    let labels: [String: String]
    let options: [String: String]
    let sizeInBytes: UInt64?

    init(_ volume: Volume) {
        self.name = volume.name
        self.driver = volume.driver
        self.format = volume.format
        self.source = volume.source
        self.creationDate = volume.createdAt
        self.labels = volume.labels
        self.options = volume.options
        self.sizeInBytes = volume.sizeInBytes
    }

    enum CodingKeys: String, CodingKey {
        case name
        case driver
        case format
        case source
        case creationDate
        case labels
        case options
        case sizeInBytes
    }
}
