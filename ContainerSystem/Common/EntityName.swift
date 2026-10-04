//
//  EntityName.swift
//  ContainerSystem
//
//  Created by Axel Martinez on 2026/08/26.
//

import Foundation

/// The name a container or a volume can be given.
public enum EntityName {
    public static let pattern = "^[A-Za-z0-9][A-Za-z0-9_.-]*$"
    public static let maximumLength = 255

    public static func isValid(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= maximumLength else { return false }

        return name.range(of: pattern, options: .regularExpression) != nil
    }

    public static func valid(from name: String) -> String {
        let kept = name.filter { character in
            character.isASCII
                && (character.isLetter || character.isNumber
                    || character == "_" || character == "."
                    || character == "-")
        }

        let start =
            kept.firstIndex { $0.isLetter || $0.isNumber } ?? kept.endIndex

        return String(kept[start...].prefix(maximumLength))
    }
}
