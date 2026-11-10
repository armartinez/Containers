//
//  ByteSize.swift
//  Containers
//
//  Created by Axel Martinez on 2026/10/30.
//

import Foundation

/// Sizes written with binary units.
enum ByteSize {
    /// Reads a number with an optional binary unit, such as `512m`, `2048MB` or `10GiB`, as bytes.
    ///
    /// - Returns: The size, or `nil` if the text isn't one.
    static func bytes(from text: String) -> UInt64? {
        let units: [Character: UnitInformationStorage] = [
            "b": .bytes, "k": .kibibytes, "m": .mebibytes, "g": .gibibytes, "t": .tebibytes, "p": .pebibytes,
        ]
        let text = text.trimmingCharacters(in: .whitespaces).lowercased()
        let unitStart = text.firstIndex { !"0123456789.".contains($0) } ?? text.endIndex
        let unitText = text[unitStart...].trimmingCharacters(in: .whitespaces)
        let unitSymbol = unitText.first ?? "b"

        guard let number = Double(text[..<unitStart].trimmingCharacters(in: .whitespaces)),
            ["", "ib", "b"].contains(unitText.dropFirst()),
            let unit = units[unitSymbol]
        else {
            return nil
        }

        return UInt64(Measurement(value: number, unit: unit).converted(to: .bytes).value)
    }
}
