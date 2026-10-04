//
//  ImageInfo.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/14.
//

import ContainerSystem
import SwiftUI

struct ImageInfo: View {
    let image: ImageItem

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            InfoSection {
                InfoRow(label: "Tag", value: image.tag)
                InfoRow(
                    label: "Digest",
                    value: image.indexDigest.digestHex
                )
                InfoRow(label: "Size", value: image.formattedSize)
                InfoRow(label: "Created", value: image.formattedCreated)
            }
        }
        .padding(20)
    }
}
