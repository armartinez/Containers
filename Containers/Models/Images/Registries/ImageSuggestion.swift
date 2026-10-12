//
//  ImageSuggestion.swift
//  Containers
//
//  Created by Axel Martinez on 01/08/2026.
//

import Foundation

/// An image a registry suggests, as the trending cards show it.
nonisolated struct ImageSuggestion: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let publisher: String?
    let description: String?
    let imageURL: URL?
}
