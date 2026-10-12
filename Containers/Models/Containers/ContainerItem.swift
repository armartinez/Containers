//
//  ContainerItem.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import ContainerSystem
import Containerization
import ContainerizationExtras
import ContainerizationOCI
import Foundation

/// Nonisolated so that a column can sort by one of its fields: the target
/// takes its types as main-actor by default, and a key path into one of those
/// is not the sendable key path a sort comparator asks for.
nonisolated struct ContainerItem: Identifiable, Hashable, Equatable, Sendable {
    let id: String
    let imageName: String
    let status: ContainerStatus
    let ports: String
    let ipAddress: String?
    let os: String
    let arch: String
    let startedDate: Date?

    /// Whether the container exists yet, rather than the row standing in for one still being made.
    private(set) var exists = true

    /// Set while work on the container is under way or has failed: its
    /// making, which the row stands in for until it is made, or a start.
    var activity: ActivitySnapshot?

    /// A container is known by its id once it exists; until then it is known
    /// by what it was asked to be called.
    var name: String { activity?.title ?? id }

    /// A row that only stands for the work of making a container.
    var isPending: Bool { activity != nil && !exists }

    /// A row for a container that is still being made, which has none of what
    /// a made one is described by.
    init(pending activity: ActivitySnapshot) {
        self.id = activity.id
        self.imageName = activity.subtitle
        self.status = .unknown
        self.ports = ""
        self.ipAddress = nil
        self.os = Platform.current.os
        self.arch = Platform.current.architecture
        self.startedDate = nil
        self.activity = activity
        self.exists = false
    }

    init(_ snapshot: ContainerSnapshot) {
        self.id = snapshot.configuration.id
        self.imageName = snapshot.configuration.image.reference
        self.status = snapshot.status
        self.ports = snapshot.configuration.publishedPorts.map {
            "\($0.hostAddress):\($0.hostPort)\u{2192}\($0.containerPort)/\($0.proto.rawValue)"
        }.joined(separator: "\n")
        self.ipAddress = snapshot.networks.first.map { network in
            let addressString = network.ipv4Address.description
            return String(
                addressString.split(separator: "/").first
                    ?? Substring(addressString)
            )
        }
        self.os = snapshot.configuration.platform.os
        self.arch = snapshot.configuration.platform.architecture
        self.startedDate = snapshot.startedDate
        self.activity = nil
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(status)
        hasher.combine(activity)
    }

    static func == (lhs: ContainerItem, rhs: ContainerItem) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status && lhs.activity == rhs.activity
    }
}

// MARK: - Display Formatting

extension ContainerItem {
    var formattedPorts: String {
        ports.isEmpty ? "-" : ports
    }

    var hasIPAddress: Bool {
        ipAddress != nil
    }

    var formattedIPAddress: String {
        ipAddress ?? "-"
    }

    var formattedOS: String {
        os.localizedCapitalized
    }

    /// What the Uptime column sorts by: one never started sorts oldest.
    var startedSort: Date {
        startedDate ?? .distantPast
    }

    var formattedState: String {
        status.rawValue.localizedCapitalized
    }

    var formattedStarted: String {
        guard let startedDate else {
            return ""
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: startedDate)
    }

    func formattedUptime(at date: Date = Date()) -> String {
        guard status == .running, let startedDate else {
            return "-"
        }

        let interval = max(0, date.timeIntervalSince(startedDate))
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: interval) ?? "-"
    }
}
