//
//  Report.swift
//  Containers
//
//  Created by Axel Martinez on 16/09/2026.
//

import Foundation

public struct Report: Identifiable, Sendable, Hashable {
    public enum Kind: String, Sendable, CaseIterable {
        case build
        case image
        case container
        case volume

        public var title: String {
            switch self {
            case .build: "Build"
            case .image: "Image"
            case .container: "Container"
            case .volume: "Volume"
            }
        }

        /// How the kind is written in the manifest.
        var domainType: String {
            "app.containers.ReportDomainType.\(rawValue.localizedCapitalized)"
        }

        init?(domainType: String) {
            guard let name = domainType.components(separatedBy: ".").last?.lowercased() else {
                return nil
            }

            self.init(rawValue: name)
        }
    }

    public enum Level: String, Sendable, CaseIterable {
        case warning
        case error

        public var title: String {
            switch self {
            case .warning: "Warning"
            case .error: "Error"
            }
        }

        /// The letter the manifest keeps
        var status: String {
            switch self {
            case .warning: "W"
            case .error: "E"
            }
        }

        init?(status: String) {
            switch status {
            case "W": self = .warning
            case "E": self = .error
            default: return nil
            }
        }
    }

    public let id: String
    public let date: Date
    public let endDate: Date
    public let level: Level
    public let kind: Kind
    public let name: String
    public let message: String
    public let isRead: Bool

    public init(
        id: String,
        date: Date,
        endDate: Date,
        level: Level,
        kind: Kind,
        name: String,
        message: String,
        isRead: Bool = false
    ) {
        self.id = id
        self.date = date
        self.endDate = endDate
        self.level = level
        self.kind = kind
        self.name = name
        self.message = message
        self.isRead = isRead
    }
}
