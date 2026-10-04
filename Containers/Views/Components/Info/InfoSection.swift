//
//  InfoSection.swift
//  Containers
//
//  Created by Axel Martinez on 20/5/26.
//

import SwiftUI

struct InfoSection<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.bottom, 6)
    }
}

#Preview {
    InfoSection {
        InfoRow(label: "Test title", value: "Test value")
        InfoRow(label: "Test title 2", value: "Test value 2")
    }
}
