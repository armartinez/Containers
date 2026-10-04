//
//  ImageHistory.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/12.
//

import ContainerSystem
import Containerization
import ContainerizationOCI
import SwiftUI

struct ImageHistory: View {
    let imageReference: String
    let platform: Platform

    @Environment(ImageManager.self) private var imageManager

    @SwiftUI.State private var layers: [LayerInfo] = []
    @SwiftUI.State private var isLoading = true
    @SwiftUI.State private var errorAlert: ErrorAlert?

    struct LayerInfo: Identifiable {
        let id = UUID()
        let digest: String?
        let size: Int64
        let command: String?
        let comment: String?
        let emptyLayer: Bool

        var formattedDigest: String {
            digest?.trimmedDigest ?? "<missing>"
        }

        var formattedSize: String {
            ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
    }

    var body: some View {
        Group {
            if isLoading {
                // Hidden by the window until ready, so nothing to draw.
                Color.clear
            } else if layers.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "square.stack.3d.up.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("No layers found")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Unable to retrieve layer information for this image")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(layers.enumerated()), id: \.element.id) {
                            index,
                            layer in
                            layerRow(layer: layer, index: index)
                        }
                    }
                    .padding(20)
                }
            }
        }
        // The layers run to any length, so the tab's bound is what it opens
        // at — and, as with inspect, dragging the window taller shows more of
        // them rather than padding the window out.
        .contentUnbounded()
        .contentReady(!isLoading)
        .task {
            await loadLayers()
        }
        .errorAlert($errorAlert)
    }

    private func layerRow(layer: LayerInfo, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                // Layer number badge
                Text("\(index + 1)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(Color.accentColor)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if let command = layer.command, !command.isEmpty {
                            Text(command)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .truncationMode(.tail)
                        } else if layer.emptyLayer {
                            Text("Metadata step")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(layer.formattedDigest)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.primary)
                        }

                        Spacer()

                        Text(layer.formattedSize)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    if let comment = layer.comment, !comment.isEmpty {
                        Text(comment)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .italic()
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }

    private func sectionHeader(title: String, subtitle: String?) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadLayers() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let layerInfo = try await imageManager.getImageLayers(
                imageReference: imageReference,
                platform: platform
            )

            // Convert ImageLayerDetail to LayerInfo
            self.layers = layerInfo.map { detail in
                LayerInfo(
                    digest: detail.digest,
                    size: detail.size,
                    command: detail.createdBy,
                    comment: detail.comment,
                    emptyLayer: detail.emptyLayer
                )
            }

        } catch {
            self.errorAlert = ErrorAlert(
                "The image history couldn’t be loaded.",
                error: error
            )
            self.layers = []
        }
    }
}
