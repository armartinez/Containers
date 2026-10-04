//
//  RegistryLookup.swift
//  Containers
//
//  Created by Axel Martinez on 29/09/2026.
//

import Foundation
import Observation

/// Asks a registry what the Pull sheet offers: what is trending, and what matches the image and tag being typed.
@Observable
@MainActor
final class RegistryLookup {
    private(set) var trendingImages: [ImageSuggestion] = []
    private(set) var isLoading = false

    @ObservationIgnored private var trendingRegistry: Registry?

    func loadTrendingImages(on registry: Registry) async {
        if registry != trendingRegistry {
            trendingRegistry = registry
            trendingImages = []
        }

        isLoading = true

        let provider = registry.provider
        var images: [ImageSuggestion] = []

        if let request = provider.trendingImages,
            let current = try? await Self.perform(request)
        {
            images = current
        }

        images = await Self.withLogos(images, from: provider)

        // A newer load has taken over.
        guard !Task.isCancelled else { return }

        trendingImages = withoutSharedArtwork(images)
        isLoading = false
    }

    func images(matching text: String, on registry: Registry) async throws -> [String] {
        guard let request = registry.provider.imageSearch(matching: text) else {
            return []
        }

        return try await Self.perform(request)
    }

    func tags(
        for imageName: String,
        matching text: String,
        on registry: Registry
    ) async throws -> [String] {
        guard
            let request = registry.provider.tagSearch(for: imageName, matching: text)
        else {
            return []
        }

        return try await Self.perform(request)
    }

    private nonisolated static let fetchedAtKey = "fetchedAt"

    /// Reuses an answer kept in the URL cache while the request says it is
    /// still good. The registry's own cache headers aren't what decides that,
    /// so the cache is read and written here rather than left to the session.
    private static func perform<Response: Sendable>(
        _ request: RegistryRequest<Response>
    ) async throws -> Response {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData

        if let lifetime = request.lifetime,
            let cached = URLCache.shared.cachedResponse(for: urlRequest),
            let fetchedAt = cached.userInfo?[fetchedAtKey] as? Date,
            .seconds(Date.now.timeIntervalSince(fetchedAt)) < lifetime,
            let response = try? request.decode(cached.data)
        {
            return response
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RegistryError.unavailable
        }

        guard httpResponse.statusCode == 200 else {
            throw httpResponse.statusCode == 429
                ? RegistryError.rateLimited : RegistryError.unavailable
        }

        let decoded = try request.decode(data)

        if request.lifetime != nil {
            URLCache.shared.storeCachedResponse(
                CachedURLResponse(
                    response: response,
                    data: data,
                    userInfo: [fetchedAtKey: Date.now],
                    storagePolicy: .allowed
                ),
                for: urlRequest
            )
        }

        return decoded
    }

    private nonisolated static func withLogos(
        _ images: [ImageSuggestion],
        from provider: any RegistryProvider
    ) async -> [ImageSuggestion] {
        await withTaskGroup(of: (Int, URL?).self) { group in
            for (index, image) in images.enumerated() where image.imageURL == nil {
                guard let request = provider.logo(for: image.name) else { continue }

                group.addTask {
                    (index, (try? await perform(request)) ?? nil)
                }
            }

            var withLogos = images

            for await (index, logo) in group {
                guard let logo else { continue }

                let image = withLogos[index]
                withLogos[index] = ImageSuggestion(
                    name: image.name,
                    publisher: image.publisher,
                    description: image.description,
                    imageURL: logo
                )
            }

            return withLogos
        }
    }

    /// A publisher's repositories often scrape the same logo, and a row of
    /// identical icons reads as a bug. Drop the artwork they share so those
    /// fall back to initials, keeping the ones that are actually distinct.
    private func withoutSharedArtwork(
        _ images: [ImageSuggestion]
    ) -> [ImageSuggestion] {
        let counts = images.reduce(into: [URL: Int]()) { counts, image in
            if let url = image.imageURL {
                counts[url, default: 0] += 1
            }
        }

        return images.map { image in
            guard let url = image.imageURL, counts[url, default: 0] > 1 else {
                return image
            }

            return ImageSuggestion(
                name: image.name,
                publisher: image.publisher,
                description: image.description,
                imageURL: nil
            )
        }
    }
}
