//
//  PullImageView.swift
//  Containers
//
//  Created by Axel Martinez on 27/06/2026.
//

import ContainerizationOCI
import SwiftUI

struct PullImageView: View {
    let shouldLoadFeaturedImages: Bool

    @Binding var imageName: String
    @Binding var tag: String
    @Binding var platform: PlatformSelection

    @SwiftUI.State private var registry: Registry = .dockerHub
    @SwiftUI.State private var registryLookup = RegistryLookup()
    @SwiftUI.State private var featuredImagePage: Int = 0

    @FocusState private var isImageNameFieldFocused: Bool
    @FocusState private var isTagFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Held against the title's rule rather than centred with the rest,
            // so what sits between the two rules is the section itself.
            featuredImageContent
                .frame(height: 156)
                // Tinted rather than given a background colour: the sheet
                // draws its own, and a named one resolves to the same white.
                //
                // Filled before the frame is pulled up so the grey covers the
                // band itself, and spread past the sheet's padding to meet its
                // edges without widening the cards.
                .background(
                    Color.primary.opacity(0.05)
                        .padding(.horizontal, -Self.sheetContentPadding)
                )
                .padding(.top, -Self.sheetContentPadding)

            FormStack {
                FormRow(title: "Registry") {
                    FormPicker(
                        placeholder: "Registry",
                        options: Registry.allCases,
                        selection: $registry
                    )
                }

                registryImageNameField

                registryTagField

                FormRow(title: "Platform") {
                    FormPicker(
                        placeholder: "Platform",
                        options: platformOptions,
                        selection: $platform
                    )
                }
            }
            // The form takes what the section leaves and centres in it.
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: shouldLoadFeaturedImages ? registry : nil) {
            guard shouldLoadFeaturedImages else { return }

            featuredImagePage = 0
            await registryLookup.loadTrendingImages(on: registry)
        }
    }

    private var platformOptions: [PlatformSelection] {
        var options: [PlatformSelection] = [.any, .platform(.current)]

        if Platform.current.architecture == "arm64" {
            options.append(.platform(Platform(arch: "amd64", os: "linux")))
        }

        return options
    }

    /// What `CreateView` insets its content by, which the section has to undo
    /// to meet the sheet's edges.
    private static let sheetContentPadding: CGFloat = 20

    /// What each page arrow takes out of the row it sits beside.
    private static let pageControlWidth: CGFloat = 28

    private let featuredImagesPerPage = 5

    private var featuredPageCount: Int {
        max(
            1,
            (registryLookup.trendingImages.count + featuredImagesPerPage - 1)
                / featuredImagesPerPage
        )
    }

    private var currentPageImages: [ImageSuggestion] {
        let start = featuredImagePage * featuredImagesPerPage
        let end = min(
            start + featuredImagesPerPage,
            registryLookup.trendingImages.count
        )
        guard start < end else { return [] }
        return Array(registryLookup.trendingImages[start..<end])
    }

    private func featuredPageButton(
        _ systemName: String,
        step: Int,
        isDisabled: Bool
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                featuredImagePage += step
            }
        } label: {
            Image(systemName: systemName)
                .imageScale(.large)
                .foregroundStyle(
                    isDisabled ? Color(nsColor: .separatorColor) : .secondary
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    @ViewBuilder
    private var featuredImageContent: some View {
        VStack(spacing: 10) {
            VStack(spacing: 10) {
                HStack {
                    Spacer()
                    Text("Trending this week on \(registry.description)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Spacer()
                }

                if !registryLookup.trendingImages.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(currentPageImages) { image in
                            FeaturedImageCard(image: image) {
                                selectRegistryImage(image.name)
                            }
                        }
                    }
                    .padding(
                        .horizontal,
                        featuredPageCount > 1 ? Self.pageControlWidth : 0
                    )
                    .overlay {
                        if featuredPageCount > 1 {
                            HStack(spacing: 0) {
                                featuredPageButton(
                                    "arrow.left.circle.fill",
                                    step: -1,
                                    isDisabled: featuredImagePage == 0
                                )

                                Spacer(minLength: 0)

                                featuredPageButton(
                                    "arrow.right.circle.fill",
                                    step: 1,
                                    isDisabled: featuredImagePage
                                        >= featuredPageCount - 1
                                )
                            }
                        }
                    }
                } else if registryLookup.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 108)
                } else {
                    Text("No suggestions available")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 108)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
                .padding(.horizontal, -Self.sheetContentPadding)
        }
    }

    private var registryImageNameField: some View {
        FormRow(title: "Image Name") {
            TextField(
                text: $imageName,
                prompt: Text("Ex: nginx, ubuntu, redis")
            ) {
                EmptyView()
            }
            .suggestions(for: isImageNameFieldFocused ? imageName : nil) {
                [registryLookup, registry] text in
                try await registryLookup.images(matching: text, on: registry)
                    .filter { $0 != text }
            }
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .focused($isImageNameFieldFocused)
            .onChange(of: imageName) { oldValue, newValue in
                if oldValue != newValue, tag != "latest" {
                    tag = "latest"
                }
            }
        }
    }

    private func selectRegistryImage(_ name: String) {
        isImageNameFieldFocused = false
        isTagFieldFocused = false
        imageName = name
        tag = "latest"
    }

    @ViewBuilder
    private var registryTagField: some View {
        FormRow(title: "Tag") {
            TextField(
                text: $tag,
                prompt: Text("Ex: latest, 1.0, stable")
            ) {
                EmptyView()
            }
            .suggestions(for: isTagFieldFocused ? tag : nil) {
                [registryLookup, registry, imageName] text in
                try await registryLookup.tags(
                    for: imageName,
                    matching: text,
                    on: registry
                )
            }
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .focused($isTagFieldFocused)
        }
    }
}

private struct FeaturedImageCard: View {
    let image: ImageSuggestion
    let action: () -> Void

    private let artworkSize: CGFloat = 44
    private let artworkRadius: CGFloat = 10

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                artwork
                    .frame(width: artworkSize, height: artworkSize)
                    .clipShape(shape)

                VStack(spacing: 1) {
                    Text(image.name)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    // Kept in the layout when absent so every card is the
                    // same height whatever the registry returns.
                    Group {
                        if let publisher = image.publisher {
                            Text(publisher)
                        } else {
                            Text("Publisher").hidden()
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
            }
            .multilineTextAlignment(.center)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background {
                card.fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
            }
            .overlay(card.strokeBorder(.quaternary, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var card: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: artworkRadius, style: .continuous)
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = image.imageURL {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                initials
            }
        } else {
            initials
        }
    }

    private var initials: some View {
        Text(initialsText)
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tint.opacity(0.18))
    }

    private var initialsText: String {
        let components = image.name
            .split(separator: "/", omittingEmptySubsequences: true)
            .suffix(2)

        let initials = components.compactMap { $0.first.map(String.init) }
            .joined()

        return initials.isEmpty ? "I" : initials.uppercased()
    }

    private var tint: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal]
        let value = image.name.unicodeScalars.reduce(0) { result, scalar in
            result + Int(scalar.value)
        }

        return colors[value % colors.count]
    }
}
