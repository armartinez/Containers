//
//  BuildDockerfileView.swift
//  Containers
//
//  Created by Axel Martinez on 27/06/2026.
//

import ContainerizationOCI
import ContainersCore
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
            .onChange(of: dockerFile) { oldDockerFile, _ in
                // Replacing the Dockerfile clears the build directory, so it falls back to
                // suggesting the new Dockerfile's folder. The first pick keeps it, since the
                // Dockerfile may have been suggested from the build directory itself.
                guard oldDockerFile != nil else { return }
                contextDirectory = nil
            }

            FormRow(title: "Build directory") {
                FileSelection(
                    placeholder: (dockerFileDirectory ?? FileSelection.userHomeDirectory).path(percentEncoded: false),
                    fileURL: $contextDirectory,
                    canChooseDirectories: true,
                    canCreateDirectories: true,
                    defaultDirectory: dockerFileDirectory ?? defaultFileDialogDirectory,
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
                title: "Image name",
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

            FormRow(title: "Target stage") {
                FormField(placeholder: "Ex: production", value: $targetStage)
            }
        }
    }

    /// The folder containing the selected Dockerfile, suggested as the build directory. It's only
    /// a suggestion: the sandbox grants access to the Dockerfile alone, so the folder still has to
    /// be chosen in the open panel before the build can read it.
    private var dockerFileDirectory: URL? {
        dockerFile?.deletingLastPathComponent()
    }

    private var platformOptions: [PlatformSelection] {
        var options: [PlatformSelection] = [.platform(.current)]

        if Platform.current.architecture == "arm64" {
            options.append(.platform(Platform(arch: "amd64", os: "linux")))
        }

        return options
    }

}
