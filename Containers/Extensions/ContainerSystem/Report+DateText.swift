//
//  Report+DateText.swift
//  Containers
//
//  Created by Axel Martinez on 02/10/2026.
//

import ContainerSystem
import Foundation

extension Report {
    /// Shared by the table and date searches, so they match.
    var dateText: String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
