//
//  WhatsNewView.swift
//  Containers
//
//  Created by Axel Martinez on 22/07/2026.
//

import AppKit
import SwiftUI

struct WhatsNewView: View {
    let onContinue: () -> Void
    let foregroundColor: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .center, spacing: 8) {
                    Text(AppInfo.release.title)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(foregroundColor)
                    Text("Containers")
                        .font(.title)
                        .fontWeight(.bold)
                }

                VStack(alignment: .leading, spacing: 20) {
                    ForEach(AppInfo.release.features, id: \.title) { feature in
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

    private func featureRow(_ feature: AppInfo.Feature) -> some View {
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

#Preview {
    WhatsNewView(onContinue: {})
}
