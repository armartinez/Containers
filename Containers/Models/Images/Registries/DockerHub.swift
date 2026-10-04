//
//  DockerHub.swift
//  Containers
//
//  Created by Axel Martinez on 27/06/2026.
//

import Foundation

nonisolated struct DockerHub: RegistryProvider {
    /// Trending is a weekly list, and the logos behind it cost a request per
    /// image on top of the list itself, so both are worth keeping a while.
    private static let cacheLifetime: Duration = .seconds(30 * 60)

    private struct FeaturedResponse: Decodable {
        let summaries: [FeaturedImage]?
        let results: [FeaturedImage]?
    }

    private struct FeaturedImage: Decodable {
        let name: String?
        let slug: String?
        let shortDescription: String?
        let description: String?
        let publisher: String?
        let publisherName: String?
        let imageURL: String?
        let logoURL: String?
        let thumbnailURL: String?
        let iconURL: String?

        enum CodingKeys: String, CodingKey {
            case name
            case slug
            case shortDescription = "short_description"
            case description
            case publisher
            case publisherName = "publisher_name"
            case imageURL = "image_url"
            case logoURL = "logo_url"
            case thumbnailURL = "thumbnail_url"
            case iconURL = "icon_url"
            case image
            case logo
            case thumbnail
            case icon
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = Self.decodeString(from: container, forKey: .name)
            slug = Self.decodeString(from: container, forKey: .slug)
            shortDescription = Self.decodeString(
                from: container,
                forKey: .shortDescription
            )
            description = Self.decodeString(
                from: container,
                forKey: .description
            )
            publisher = Self.decodeString(from: container, forKey: .publisher)
            publisherName = Self.decodeString(
                from: container,
                forKey: .publisherName
            )
            imageURL =
                Self.decodeString(from: container, forKey: .imageURL)
                ?? Self.decodeString(from: container, forKey: .image)
            logoURL =
                Self.decodeString(from: container, forKey: .logoURL)
                ?? Self.decodeString(from: container, forKey: .logo)
            thumbnailURL =
                Self.decodeString(from: container, forKey: .thumbnailURL)
                ?? Self.decodeString(from: container, forKey: .thumbnail)
            iconURL =
                Self.decodeString(from: container, forKey: .iconURL)
                ?? Self.decodeString(from: container, forKey: .icon)
        }

        private static func decodeString(
            from container: KeyedDecodingContainer<CodingKeys>,
            forKey key: CodingKeys
        ) -> String? {
            try? container.decodeIfPresent(String.self, forKey: key)
        }

        var suggestion: ImageSuggestion? {
            guard let imageName = slug ?? name else {
                return nil
            }

            return ImageSuggestion(
                name: imageName,
                publisher: publisherName ?? publisher,
                description: shortDescription ?? description,
                imageURL: [imageURL, thumbnailURL, iconURL, logoURL]
                    .compactMap {
                        $0?.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    .first { !$0.isEmpty }
                    .flatMap(URL.init(string:))
            )
        }
    }

    private struct ImageSearchResponse: Decodable {
        let results: [ImageSearchResult]
    }

    private struct ImageSearchResult: Decodable {
        let repoName: String

        enum CodingKeys: String, CodingKey {
            case repoName = "repo_name"
        }
    }

    private struct TagResponse: Decodable {
        let results: [Tag]
    }

    private struct Tag: Decodable {
        let name: String
    }

    private struct RepositoryDetail: Decodable {
        let fullDescription: String?

        enum CodingKeys: String, CodingKey {
            case fullDescription = "full_description"
        }
    }

    private func hubURL(path: String, query: [URLQueryItem] = []) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "hub.docker.com"
        components.path = path

        // An empty list would still leave a `?` on the end.
        if !query.isEmpty {
            components.queryItems = query
        }

        return components.url
    }

    private func pathComponents(of imageName: String) -> [String] {
        imageName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
    }

    /// Docker Hub addresses a repository as `namespace/name`, defaulting the
    /// namespace to `library`. Nothing outside this type needs to know that.
    private func repository(from imageName: String) -> Repository? {
        let components = pathComponents(of: imageName)

        let namespace: String
        let name: String
        switch components.count {
        case 1:
            namespace = "library"
            name = components[0]
        case 2:
            namespace = components[0]
            name = components[1]
        default:
            return nil
        }

        // The tag has a field of its own, but a pasted name may carry one.
        let repositoryName =
            name
            .split(
                separator: ":",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )
            .first
            .map(String.init) ?? name

        guard !namespace.isEmpty, !repositoryName.isEmpty else {
            return nil
        }

        return Repository(namespace: namespace, name: repositoryName)
    }

    func imageSearch(matching text: String) -> RegistryRequest<[String]>? {
        // The registry is picked in its own field, so a name is
        // `[namespace/]name`; anything deeper is not a Docker Hub repository.
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = pathComponents(of: query)

        guard !path.isEmpty, path.count <= 2 else {
            return nil
        }

        guard
            let url = hubURL(
                path: "/v2/search/repositories/",
                query: [
                    URLQueryItem(name: "query", value: query),
                    URLQueryItem(name: "page_size", value: "10"),
                ]
            )
        else {
            return nil
        }

        return RegistryRequest(url: url) { data in
            let decoded = try JSONDecoder().decode(
                ImageSearchResponse.self,
                from: data
            )
            return ranked(decoded.results.map(\.repoName), matching: query)
        }
    }

    func tagSearch(
        for imageName: String,
        matching text: String
    ) -> RegistryRequest<[String]>? {
        guard let repository = repository(from: imageName) else {
            return nil
        }

        let prefix = text.trimmingCharacters(in: .whitespacesAndNewlines)

        var query = [URLQueryItem(name: "page_size", value: "20")]

        if !prefix.isEmpty {
            query.append(URLQueryItem(name: "name", value: prefix))
        }

        guard
            let url = hubURL(
                path:
                    "/v2/repositories/\(repository.namespace)/\(repository.name)/tags/",
                query: query
            )
        else {
            return nil
        }

        return RegistryRequest(url: url) { data in
            let decoded = try JSONDecoder().decode(TagResponse.self, from: data)
            return ranked(
                decoded.results.map(\.name),
                matching: prefix,
                pinning: "latest"
            )
        }
    }

    var trendingImages: RegistryRequest<[ImageSuggestion]>? {
        guard
            let url = hubURL(
                path: "/api/content/v1/products/search",
                query: [
                    URLQueryItem(name: "page_size", value: "25"),
                    URLQueryItem(name: "q", value: ""),
                    URLQueryItem(name: "source", value: "community"),
                    URLQueryItem(name: "type", value: "image,model"),
                    URLQueryItem(name: "sort", value: "trending"),
                ]
            )
        else {
            return nil
        }

        return RegistryRequest(url: url, lifetime: Self.cacheLifetime) {
            data in
            let decoded = try JSONDecoder().decode(
                FeaturedResponse.self,
                from: data
            )
            let products = decoded.summaries ?? decoded.results ?? []
            let suggestions = products.compactMap(\.suggestion)

            // Not an answer worth keeping: it would leave the strip empty
            // until it expired.
            guard !suggestions.isEmpty else { throw RegistryError.unavailable }

            return suggestions
        }
    }

    /// Docker Hub has no logo field for a repository, so the first image in
    /// its description stands in for one.
    func logo(for imageName: String) -> RegistryRequest<URL?>? {
        guard let repository = repository(from: imageName) else {
            return nil
        }

        guard
            let url = hubURL(
                path:
                    "/v2/repositories/\(repository.namespace)/\(repository.name)/"
            )
        else {
            return nil
        }

        return RegistryRequest(url: url, lifetime: Self.cacheLifetime) {
            data in
            let detail = try JSONDecoder().decode(
                RepositoryDetail.self,
                from: data
            )
            return firstMarkdownImageURL(in: detail.fullDescription)
        }
    }

    /// Docker Hub returns search hits in its own relevance order and tags by
    /// last push. Keep that order, but float what the user is most likely
    /// reaching for, and never list the same thing twice.
    private func ranked(
        _ values: [String],
        matching text: String,
        pinning pinned: String? = nil
    ) -> [String] {
        var seen = Set<String>()

        return
            values
            .filter { seen.insert($0).inserted }
            .enumerated()
            .sorted { lhs, rhs in
                let lhsRank = rank(lhs.element, matching: text, pinned: pinned)
                let rhsRank = rank(rhs.element, matching: text, pinned: pinned)

                return lhsRank == rhsRank
                    ? lhs.offset < rhs.offset : lhsRank < rhsRank
            }
            .map(\.element)
    }

    private func rank(
        _ value: String,
        matching text: String,
        pinned: String?
    ) -> Int {
        if value == pinned { return 0 }
        if value == text { return 1 }
        if !text.isEmpty, value.hasPrefix(text) { return 2 }
        return 3
    }

    private func firstMarkdownImageURL(in markdown: String?) -> URL? {
        guard let markdown else { return nil }

        let pattern = #"!\[[^\]]*\]\(([^\s)]+)(?:\s+\"[^\"]*\")?\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(
            markdown.startIndex..<markdown.endIndex,
            in: markdown
        )
        guard let match = regex.firstMatch(in: markdown, range: range),
            match.numberOfRanges > 1,
            let urlRange = Range(match.range(at: 1), in: markdown)
        else {
            return nil
        }

        let value = String(markdown[urlRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: value)
    }

    private struct Repository {
        let namespace: String
        let name: String
    }
}
