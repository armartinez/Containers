//
//  VolumeMount.swift
//  Containers
//
//  Created by Axel Martinez on 03/08/2026.
//

import Foundation

struct VolumeMount: Identifiable {
    enum Source: String, CaseIterable, Hashable, CustomStringConvertible {
        case volume = "Volume"
        case anonymousVolume = "Anonymous Volume"

        var description: String { rawValue }
    }

    let id: UUID = UUID()
    var source: Source = .volume
    var volumeName: String = ""
    var target: String = ""

    var summary: String {
        trimmedTarget.isEmpty
            ? sourceLabel : "\(sourceLabel) -> \(trimmedTarget)"
    }

    var columns: [String] {
        [sourceLabel, trimmedTarget]
    }

    var sourceLabel: String {
        switch source {
        case .volume:
            trimmedVolumeName.isEmpty ? "No Volume" : trimmedVolumeName
        case .anonymousVolume:
            "Anonymous Volume"
        }
    }

    var trimmedVolumeName: String {
        volumeName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedTarget: String {
        target.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
