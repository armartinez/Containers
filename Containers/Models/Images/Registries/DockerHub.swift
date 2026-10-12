//
//  DockerHub.swift
//  Containers
//
//  Created by Axel Martinez on 27/06/2026.
//

import Foundation

nonisolated struct DockerHub: RegistryProvider {
    private static let cacheLifetime: Duration = .seconds(30 * 60)

    /// Docker Official Images are published under `library`, which reads as
    /// nothing to anyone who doesn't already know that.
    private static let officialPublisher = "library"

    private struct PopularResponse: Decodable {
        let results: [PopularImage]
    }

    private struct PopularImage: Decodable {
        let slug: String
        let shortDescription: String?
        let publisher: Publisher?
        let logoURL: Logo?

        struct Publisher: Decodable {
            let name: String?
        }

        struct Logo: Decodable {
            let large: String?
            let small: String?
        }

        enum CodingKeys: String, CodingKey {
            case slug
            case shortDescription = "short_description"
            case publisher
            case logoURL = "logo_url"
        }

        var suggestion: ImageSuggestion {
            let publisherName = publisher?.name.map {
                $0 == DockerHub.officialPublisher ? "Docker Official Image" : $0
            }

            return ImageSuggestion(
                name: slug,
                publisher: publisherName,
                description: shortDescription,
                imageURL: [logoURL?.large, logoURL?.small]
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

    var featuredImages: RegistryRequest<[ImageSuggestion]>? {
        guard
            let url = hubURL(
                path: "/api/search/v4",
                query: [
                    URLQueryItem(name: "query", value: ""),
                    URLQueryItem(name: "from", value: "0"),
                    URLQueryItem(name: "size", value: "25"),
                    URLQueryItem(name: "type", value: "image"),
                    URLQueryItem(name: "badges", value: "official,verified_publisher"),
                ]
            )
        else {
            return nil
        }

        return RegistryRequest(url: url, lifetime: Self.cacheLifetime) {
            data in
            let decoded = try JSONDecoder().decode(
                PopularResponse.self,
                from: data
            )
            let suggestions = decoded.results.map(\.suggestion)

            guard !suggestions.isEmpty else { throw RegistryError.unavailable }

            return suggestions
        }
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
            return ranked(
                decoded.results.map(\.repoName),
                matching: query.lowercased()
            )
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

    /// Docker Hub has no logo field for a repository, so the first image in its description stands in for one.
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

    /// Docker Hub returns search hits in its own relevance order and tags by last push.
    /// Keep that order, but float what the user is most likely reaching for, and never list the same thing twice.
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

                return lhsRank == rhsRank ? lhs.offset < rhs.offset : lhsRank < rhsRank
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
        guard !text.isEmpty else { return 4 }

        // Official images have no namespace, and are what a bare name means.
        let isOfficial = !value.contains("/")
        if isOfficial, value.hasPrefix(text) { return 2 }

        let name = value.split(separator: "/").last.map(String.init) ?? value
        if value.hasPrefix(text) || name.hasPrefix(text) { return 3 }
        return 4
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
