//
//  CreateImageConfiguration.swift
//  Containers
//
//  Created by Axel Martinez on 28/06/2026.
//

import ContainerSystem
import ContainerizationOCI
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct CreateImageConfiguration: View {
    let selectedMethod: CreateImageView.CreationMethod?
    let defaultFileDialogDirectory: URL?
    let tarContentTypes: [UTType]
    let shouldLoadPullFeaturedImages: Bool
    let onFileSelection: () -> Void

    @Binding var error: ErrorAlert?
    @Binding var pull: ImagePullRequest
    @Binding var build: ImageBuildRequest
    @Binding var load: ImageLoadRequest

    var body: some View {
        Group {
            switch selectedMethod {
            case .pull:
                PullImageView(
                    shouldLoadFeaturedImages: shouldLoadPullFeaturedImages,
                    imageName: $pull.imageName,
                    tag: $pull.tag,
                    platform: $pull.platform
                )
            case .build:
                BuildDockerfileView(
                    defaultFileDialogDirectory: defaultFileDialogDirectory,
                    error: $error,
                    contextDirectory: $build.contextDirectory,
                    dockerFile: $build.dockerFile,
                    buildTag: $build.tag,
                    buildPlatform: $build.platform,
                    buildArguments: $build.arguments,
                    targetStage: $build.targetStage
                )
            case .load:
                LoadTarImageView(
                    tarFile: $load.tarFile,
                    force: $load.force,
                    tarContentTypes: tarContentTypes,
                    defaultDirectory: defaultFileDialogDirectory,
                    onSelection: onFileSelection
                )
            case .none:
                EmptyView()
            }
        }
    }
}
