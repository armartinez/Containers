//
//  AppVersion.swift
//  Containers
//
//  Created by Axel Martinez on 10/10/2026.
//

import Foundation

/// A marketing version such as `1.2.3`, in the format `CFBundleShortVersionString`
/// requires: one to three period-separated integers. Missing parts are zero.
nonisolated struct AppVersion: Hashable, Comparable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

extension AppVersion: LosslessStringConvertible {
    /// Fails for anything but digits between the periods: `Int` alone would
    /// accept a sign, letting `1.-2` through.
    init?(_ description: String) {
        let components = description.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = components.compactMap { component in
            component.allSatisfy { $0.isASCII && $0.isNumber } ? Int(component) : nil
        }

        guard (1...3).contains(components.count), numbers.count == components.count else {
            return nil
        }

        self.init(
            major: numbers[0],
            minor: numbers.count > 1 ? numbers[1] : 0,
            patch: numbers.count > 2 ? numbers[2] : 0
        )
    }

    var description: String { "\(major).\(minor).\(patch)" }
}
