//
//  WhatsNewView.swift
//  Containers
//
//  Created by Axel Martinez on 22/07/2026.
//

import AppKit
import SwiftUI

struct WhatsNewView: View {
    let isFirstLaunch: Bool
    let onContinue: () -> Void

    let foregroundColor: Color = .secondary

    private struct Feature {
        let icon: String
        let title: String
        let description: String
    }

    private let features: [Feature] = [
        Feature(
            icon: "shippingbox",
            title: "Run Linux containers",
            description:
                "Create and run Linux containers as lightweight virtual machines on your Mac."
        ),
        Feature(
            icon: "cube.transparent",
            title: "OCI-compatible images support",
            description:
                "Pull and run images from container registries, build from a Dockerfile, or load from a local archive."
        ),
        Feature(
            icon: "cpu",
            title: "Optimized for Apple Silicon",
            description:
                "Written in Swift and designed to get the most out of Apple Silicon."
        ),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .center, spacing: 8) {
                    Text(isFirstLaunch ? "Welcome to" : "What's New in")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(foregroundColor)
                    Text("Containers")
                        .font(.title)
                        .fontWeight(.bold)
                }

                VStack(alignment: .leading, spacing: 20) {
                    ForEach(features, id: \.title) { feature in
                        featureRow(feature)
                    }
                }
            }

            Spacer()

            Button {
                onContinue()
            } label: {
                Text("Continue")
                    .foregroundStyle(.white)
            }
            .buttonStyle(.borderedProminent)
            .tint(foregroundColor)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 48)
        .padding(.top, 68)
        .padding(.bottom, 38)
        .frame(width: 494, height: 540)
    }

    private func featureRow(_ feature: Feature) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: feature.icon)
                .font(.system(size: 28))
                .foregroundStyle(foregroundColor)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.headline)
                Text(feature.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview("First Launch") {
    WhatsNewView(isFirstLaunch: true, onContinue: {})
}

#Preview("Update") {
    WhatsNewView(isFirstLaunch: false, onContinue: {})
}
