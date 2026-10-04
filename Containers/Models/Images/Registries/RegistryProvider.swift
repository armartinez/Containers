//
//  RegistryProvider.swift
//  Containers
//
//  Created by Axel Martinez on 01/08/2026.
//

import Foundation

/// A call to a registry's API and how to read what comes back, described
/// without being made, as a `FetchDescriptor` describes a SwiftData fetch.
nonisolated struct RegistryRequest<Response>: Sendable {
    let url: URL
    let lifetime: Duration?
    let decode: @Sendable (Data) throws -> Response

    init(
        url: URL,
        lifetime: Duration? = nil,
        decode: @escaping @Sendable (Data) throws -> Response
    ) {
        self.url = url
        self.lifetime = lifetime
        self.decode = decode
    }
}

/// Creates the requests a registry answers while the image and tag fields are
/// typed into. How a name maps onto its API is the provider's business; making
/// the calls is ``RegistryLookup``'s.
///
/// A request is nil where the registry has nothing to ask for it.
nonisolated protocol RegistryProvider: Sendable {
    var trendingImages: RegistryRequest<[ImageSuggestion]>? { get }

    func imageSearch(matching text: String) -> RegistryRequest<[String]>?
    func tagSearch(for imageName: String, matching text: String) -> RegistryRequest<[String]>?
    func logo(for imageName: String) -> RegistryRequest<URL?>?
}

/// Why a lookup could not be answered. Distinguishes a registry that would not
/// talk to us from one that simply had nothing to suggest.
nonisolated enum RegistryError: LocalizedError {
    case rateLimited
    case unavailable

    var errorDescription: String? {
        switch self {
        case .rateLimited:
            "The registry is rate limiting requests. Suggestions will come back shortly."
        case .unavailable:
            "Couldn't reach the registry."
        }
    }
}
