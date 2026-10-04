//
//  RequestScheme.swift
//  Containers
//
//  Registry request scheme configuration.
//

import Foundation

/// Represents the scheme to use when connecting to a container registry.
public enum RequestScheme: String, Sendable, Codable {
    case auto
    case http
    case https

    public init(_ value: String) throws {
        switch value.lowercased() {
        case "auto":
            self = .auto
        case "http":
            self = .http
        case "https":
            self = .https
        default:
            self = .auto
        }
    }
}
