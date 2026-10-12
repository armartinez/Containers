//
//  Capability.swift
//  Containers
//
//  Created by Axel Martinez on 03/08/2026.
//

import Foundation

struct Capability: Identifiable {
    let id: UUID = UUID()
    var name: String = ""

    var summary: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension [Capability] {
    var names: [String] {
        map(\.summary).filter { !$0.isEmpty }
    }
}
