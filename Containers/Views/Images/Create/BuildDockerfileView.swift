//
//  BuildDockerfileView.swift
//  Containers
//
//  Created by Axel Martinez on 27/06/2026.
//

import ContainerSystem
import ContainerizationOCI
import SwiftUI
import UniformTypeIdentifiers

struct BuildDockerfileView: View {
    let defaultFileDialogDirectory: URL?

    @Binding var error: ErrorAlert?
    @Binding var contextDirectory: URL?
    @Binding var dockerFile: URL?
    @Binding var buildTag: String
    @Binding var buildPlatform: PlatformSelection
    @Binding var buildArguments: [KeyValue]
    @Binding var targetStage: String

    var body: some View {
        FormStack {
            FormRow(title: "Dockerfile") {
                FileSelection(
                    placeholder: "No Dockerfile selected",
                    fileURL: $dockerFile,
                    allowedContentTypes: [.item],
                    defaultDirectory: defaultFileDialogDirectory,
                    onSelection: { error = nil }
                )
            }

            FormRow(title: "Build Directory") {
                FileSelection(
                    placeholder: FileSelection.userHomeDirectory.path(),
                    fileURL: $contextDirectory,
                    canChooseDirectories: true,
                    canCreateDirectories: true,
                    defaultDirectory: defaultFileDialogDirectory,
                    style: .field,
                    onSelection: { error = nil }
                )
            }
            .onChange(
                of: contextDirectory,
                {
                    guard let url = contextDirectory, dockerFile == nil
                    else { return }
                    // Auto-suggest Dockerfile in the build directory.
                    let dockerfileURL = url.appending(path: "Dockerfile")
                    if FileManager.default.fileExists(
                        atPath: dockerfileURL.path
                    ) {
                        self.dockerFile = dockerfileURL
                    }
                }
            )

            FormRow(
                title: "Image Name",
                description: "⭑ If empty, a generated UUID will be used"
            ) {
                FormField(
                    placeholder: "Ex: my-app, my-app:dev",
                    value: $buildTag
                )
            }

            FormRow(title: "Platform") {
                FormPicker(
                    placeholder: "Platform",
                    options: platformOptions,
                    selection: $buildPlatform
                )
            }

            FormRow(title: "Target Stage") {
                FormField(placeholder: "Ex: production", value: $targetStage)
            }
        }
    }

    private var platformOptions: [PlatformSelection] {
        var options: [PlatformSelection] = [.platform(.current)]

        if Platform.current.architecture == "arm64" {
            options.append(.platform(Platform(arch: "amd64", os: "linux")))
        }

        return options
    }

}
