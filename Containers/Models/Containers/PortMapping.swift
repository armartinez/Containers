//
//  PortMapping.swift
//  Containers
//
//  Created by Axel Martinez on 03/08/2026.
//

import ContainerSystem
import Containerization
import ContainerizationExtras
import ContainerizationOCI
import Foundation

struct PortMapping: Identifiable {
    /// The numbers a TCP or UDP port can carry.
    static let range = 1...65535

    let id: UUID = UUID()
    var hostAddress: String = "127.0.0.1"
    var host: Int = 0
    var container: Int = 0
    var publishProtocol: PublishProtocol = .tcp

    /// The port to publish, or nil for a row that cannot make one: the zeroes
    /// it starts life with, or a number no port can take.
    ///
    /// The range is checked before the conversion rather than after, because
    /// `UInt16` traps on what it cannot hold instead of reporting it.
    var publishedPort: PublishPort? {
        guard Self.range.contains(self.host),
            Self.range.contains(self.container),
            let fallbackAddress = try? IPAddress("127.0.0.1")
        else {
            return nil
        }

        let address = try? IPAddress(
            hostAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        return .init(
            hostAddress: address ?? fallbackAddress,
            hostPort: UInt16(self.host),
            containerPort: UInt16(self.container),
            proto: self.publishProtocol,
            count: 1
        )
    }

    var summary: String {
        "\(hostAddress):\(host):\(container)/\(publishProtocol.rawValue.uppercased())"
    }

    var columns: [String] {
        [
            "\(hostAddress):\(host)",
            "\(container)",
            publishProtocol.rawValue.uppercased(),
        ]
    }
}
