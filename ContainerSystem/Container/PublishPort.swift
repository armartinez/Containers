//
//  PublishPort.swift
//  Containers
//
//  Local implementation of PublishPort (replaces ContainerResource.PublishPort)
//

import ContainerizationExtras
import Foundation

/// Network protocol for published ports.
public enum PublishProtocol: String, Sendable, Codable, CaseIterable {
    case tcp
    case udp

    public init() {
        self = .tcp
    }

    public init(_ value: String) {
        switch value.lowercased() {
        case "udp":
            self = .udp
        default:
            self = .tcp
        }
    }
}

/// Represents a port forwarding rule from host to container.
public struct PublishPort: Sendable, Codable {
    public let hostAddress: IPAddress
    public let hostPort: UInt16
    public let containerPort: UInt16
    public let proto: PublishProtocol
    public let count: UInt16

    public init(
        hostAddress: IPAddress? = try? IPAddress("127.0.0.1"),
        hostPort: UInt16,
        containerPort: UInt16,
        proto: PublishProtocol = .tcp,
        count: UInt16 = 1
    ) {
        guard let hostAddress else {
            fatalError("Invalid IP Addess")
        }

        self.hostAddress = hostAddress
        self.hostPort = hostPort
        self.containerPort = containerPort
        self.proto = proto
        self.count = count
    }
}

extension PublishPort: CustomStringConvertible {
    public var description: String {
        "\(self.hostPort):\(self.containerPort) (\(self.proto.rawValue.localizedUppercase))"
    }
}

extension Array where Element == PublishPort {
    /// Check for overlapping port configurations.
    public func hasOverlaps() -> Bool {
        var seen = Set<String>()
        for port in self {
            // Counted in Int: a range reaching the top of the port range
            // would overflow UInt16 and trap on the way there.
            for offset in 0..<Int(port.count) {
                let key =
                    "\(port.hostAddress):\(Int(port.hostPort) + offset)/\(port.proto.rawValue)"
                if seen.contains(key) {
                    return true
                }
                seen.insert(key)
            }
        }
        return false
    }
}
