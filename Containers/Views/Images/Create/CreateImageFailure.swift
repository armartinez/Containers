//
//  CreateImageFailure.swift
//  Containers
//
//  Created by Axel Martinez on 24/08/2026.
//

import SwiftUI

/// What the assistant shows in place of its own content once the work it was
/// there to do has failed: what happened, said plainly, with the registry's
/// own account of it kept a click away.
struct CreateImageFailure: View {
    private static let maximumMessageHeight: CGFloat = 140
    private static let writingWidth: CGFloat = 420

    let failure: ErrorAlert

    @State private var showsDetails: Bool = false
    @State private var messageHeight: CGFloat = 0

    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 38))
            .foregroundStyle(.secondary)
            .overlay(alignment: .bottom) {
                VStack(spacing: 10) {
                    Text(failure.title)
                        .font(.headline)

                    ScrollView {
                        message
                            .onGeometryChange(for: CGFloat.self) {
                                $0.size.height
                            } action: {
                                messageHeight = $0
                            }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(
                        height: min(messageHeight, Self.maximumMessageHeight)
                    )

                    if let details = failure.details {
                        DisclosureGroup(isExpanded: $showsDetails) {
                            ScrollView {
                                Text(details)
                                    .font(
                                        .system(.caption, design: .monospaced)
                                    )
                                    .textSelection(.enabled)
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .leading
                                    )
                                    .padding(8)
                            }
                            .frame(height: 110)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(
                                        Color(nsColor: .separatorColor),
                                        lineWidth: 1
                                    )
                            )
                        } label: {
                            Text(showsDetails ? "Hide Details" : "Show Details")
                                .font(.subheadline)
                        }
                        .padding(.top, 6)
                    }
                }
                .frame(width: Self.writingWidth)
                .alignmentGuide(VerticalAlignment.bottom) { _ in
                    -CGFloat.sheetMarkSpacing
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var message: some View {
        Text(failure.message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity)
    }
}
