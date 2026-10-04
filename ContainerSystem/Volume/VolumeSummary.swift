//
//  VolumeSummary.swift
//  Containers
//
//  Created by Axel Martinez on 03/10/2026.
//

/// A volume as a list shows it: the volume, and whether a container uses it.
public struct VolumeSummary: Sendable {
    public let volume: Volume
    public let isInUse: Bool

    public init(volume: Volume, isInUse: Bool) {
        self.volume = volume
        self.isInUse = isInUse
    }
}
