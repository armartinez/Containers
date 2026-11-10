//
//  CreateImageMethodStep.swift
//  Containers
//
//  Created by Axel Martinez on 28/06/2026.
//

import SwiftUI

struct CreateImageMethod: View {
    @Binding var selectedMethod: CreateImageView.CreationMethod?

    /// Building runs the builder's virtual machine, which can't run beside the CLI's API server.
    var canBuild = true

    let onSelection: (CreateImageView.CreationMethod) -> Void

    var body: some View {
        VStack(spacing: 48) {
            VStack(spacing: 10) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 68, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(nsColor: .systemBlue))

                Text("Create an Image")
                    .font(.title)
                    .fontWeight(.semibold)

                Text("OCI-compatible images bundle your app and its dependencies into a portable, reproducible package that runs consistently across different environments.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 15) {
                Text("How do you want to add an image to your library ?")
                    .fontWeight(.bold)
                    .padding(.leading, 8)

                // A radio group ignores `disabled` on a single option, so each option is a picker
                // of its own, sharing the selection, that can be disabled as a whole.
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(CreateImageView.CreationMethod.allCases, id: \.self) { method in
                        Picker("", selection: $selectedMethod) {
                            Text(method.rawValue)
                                .font(.body)
                                .tag(method as CreateImageView.CreationMethod?)
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                        .disabled(method == .build && !canBuild)
                    }
                }
                .padding(.leading, 8)
                .onChange(of: selectedMethod) { _, newValue in
                    if let method = newValue {
                        onSelection(method)
                    }
                }

                if !canBuild {
                    Text("Images can’t be built while the container CLI is using this data folder.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                }
            }
        }
        .frame(width: 460, alignment: .center)
    }
}
#Preview {
    @Previewable @State var selectedMethod: CreateImageView.CreationMethod? =
        .pull

    CreateImageMethod(selectedMethod: $selectedMethod) { method in
        selectedMethod = method
    }
    .padding()
}
