//
//  VolumeItem.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import ContainerSystem
import Foundation

enum VolumeType: String, CaseIterable, Identifiable {
    case named = "Named"
    case anonymous = "Anonymous"

    var id: String { rawValue }
}

@dynamicMemberLookup
nonisolated struct VolumeItem: Identifiable, Hashable, Equatable, Sendable {
    let volume: Volume
    let isInUse: Bool
    var activity: ActivitySnapshot?
    var id: String { volume.id }
    var name: String { volume.name }
    var createdAt: Date { volume.createdAt }
    var sizeSort: UInt64 { volume.sizeInBytes ?? 0 }
    var typeText: String { volumeType.rawValue }
    var stateText: String { isInUse ? "In use" : "Unused" }

    var volumeType: VolumeType {
        self.volume.isAnonymous ? .anonymous : .named
    }

    var labels: [String: String] {
        self.volume.labels.filter({ $0.key != Volume.anonymousLabel })
    }

    var options: [String: String] {
        self.volume.options.filter({ $0.key != "KB" })
    }

    init(_ item: VolumeSummary) {
        self.volume = item.volume
        self.isInUse = item.isInUse
    }

    init(_ volume: Volume, isInUse: Bool = false) {
        self.volume = volume
        self.isInUse = isInUse
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(volume.id)
        hasher.combine(volume.name)
        hasher.combine(isInUse)
        hasher.combine(activity)
    }

    static func == (lhs: VolumeItem, rhs: VolumeItem) -> Bool {
        lhs.volume.id == rhs.volume.id && lhs.volume.name == rhs.volume.name
            && lhs.isInUse == rhs.isInUse && lhs.activity == rhs.activity
    }

}

extension VolumeItem {
    subscript<T>(dynamicMember keyPath: KeyPath<Volume, T>) -> T {
        volume[keyPath: keyPath]
    }
}

// MARK: - Display Formatting

extension VolumeItem {
    var formattedCreated: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        return formatter.string(from: volume.createdAt)
    }

    var formattedSize: String? {
        guard let volumeSize = volume.sizeInBytes else {
            return nil
        }

        let formattedSize = ByteCountFormatter.string(
            fromByteCount: Int64(volumeSize),
            countStyle: .file
        )

        return formattedSize
    }
}
