//
//  AppLink.swift
//  Containers
//
//  Created by Axel Martinez on 27/09/2026.
//

import Foundation

/// A link into the app, such as `containers://reports?name=redis-test`, which
/// the dashboard opens: from a detail window, or from outside the app.
enum AppLink: Equatable {
    /// The Reports section, narrowed to what was reported against `name`.
    case reports(name: String)

    static let scheme = "containers"

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme

        switch self {
        case .reports(let name):
            components.host = "reports"
            components.queryItems = [URLQueryItem(name: "name", value: name)]
        }

        // Only fails for a malformed path, which is never built here.
        return components.url ?? URL(fileURLWithPath: "/")
    }

    /// Anything not recognised is ignored: any app can open these.
    init?(_ url: URL) {
        guard url.scheme == Self.scheme, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let query = components.queryItems ?? []

        switch components.host {
        case "reports":
            guard let name = query.first(where: { $0.name == "name" })?.value, !name.isEmpty else {
                return nil
            }

            self = .reports(name: name)
        default:
            return nil
        }
    }
}
