//
//  CreateImageWizard.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import AppKit
import ContainerSystem
import Containerization
import ContainerizationError
import ContainerizationOCI
import ContainerizationOS
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct CreateImageView: View {
    let tarContentTypes = [UTType(filenameExtension: "tar")].compactMap { $0 }

    enum CreationMethod: String, CaseIterable {
        case pull = "Pull from Registry"
        case build = "Build from Dockerfile"
        case load = "Load from Tar"

        var icon: String {
            switch self {
            case .pull: return "arrow.down.circle.fill"
            case .build: return "hammer.fill"
            case .load: return "folder.fill"
            }
        }

        var description: String {
            switch self {
            case .pull: return "Download an image from a remote registry"
            case .build: return "Build an image from a Dockerfile"
            case .load: return "Load an image from a tar archive"
            }
        }
    }

    enum Step: Int, CaseIterable {
        case method = 0
        case configuration = 1

        var isCentered: Bool {
            switch self {
            case .method:
                true
            case .configuration:
                false
            }
        }
    }

    @Environment(ImageManager.self) private var imageManager
    @Environment(ActivityCenter.self) private var activityCenter
    @Environment(\.dismiss) private var dismiss

    @SwiftUI.State private var currentStep: Step = .method
    @SwiftUI.State private var stepTransitionDirection: Int = 1
    @SwiftUI.State private var selectedMethod: CreationMethod?
    @SwiftUI.State private var failure: ErrorAlert?
    @SwiftUI.State private var pull = ImagePullRequest()
    @SwiftUI.State private var build = ImageBuildRequest()
    @SwiftUI.State private var load = ImageLoadRequest()
    @SwiftUI.State private var shouldLoadPullFeaturedImages: Bool = false
    @SwiftUI.State private var paneTitle: String?

    var body: some View {
        CreateView(
            title: "Create Image",
            isFailed: failure != nil,
            width: Self.sheetWidth,
            height: 480,
            showsHeader: false,
            contentAlignment: .center,
            showsFooterDivider: false,
            contentID: AnyHashable(currentStep),
            contentTransition: stepTransition,
            contentTitle: paneTitle,
            // Only the suggestions are ruled off into their own section.
            contentTitleRule: selectedMethod == .pull,
            content: {
                currentStepContent
                    .multilineTextAlignment(.leading)
            },
            actions: {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .frame(width: .sheetButtonLabelWidth)
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(
                    action: previousStep,
                    label: {
                        Text("Previous")
                            .frame(width: .sheetButtonLabelWidth)
                    }
                )
                .buttonStyle(.bordered)
                .disabled(currentStep.rawValue == 0 && failure == nil)

                switch currentStep {
                case .method:
                    Button(
                        action: nextStep,
                        label: {
                            Text("Next")
                                .frame(width: .sheetButtonLabelWidth)
                        }
                    )
                    .defaultAction(enabled: canProceedToNextStep)
                case .configuration:
                    Button(
                        action: createImage,
                        label: {
                            Text("Create")
                                .frame(width: .sheetButtonLabelWidth)
                        }
                    )
                    .defaultAction(
                        enabled: canProceedToNextStep && failure == nil
                    )
                }
            },
            failure: {
                if let failure {
                    CreateImageFailure(failure: failure)
                }
            }
        )
    }

    private func paneTitle(for step: Step) -> String? {
        guard step == .configuration,
            selectedMethod == .build || selectedMethod == .pull
        else {
            return nil
        }

        return "Choose options for your new image"
    }

    @ViewBuilder
    private var currentStepContent: some View {
        switch currentStep {
        case .method:
            CreateImageMethod(
                selectedMethod: $selectedMethod,
                onSelection: selectCreationMethod
            )
        case .configuration:
            CreateImageConfiguration(
                selectedMethod: selectedMethod,
                defaultFileDialogDirectory:
                    defaultFileDialogDirectory,
                tarContentTypes: tarContentTypes,
                shouldLoadPullFeaturedImages: shouldLoadPullFeaturedImages,
                onFileSelection: { failure = nil },
                error: $failure,
                pull: $pull,
                build: $build,
                load: $load
            )
        }
    }

    private static let sheetWidth: CGFloat = 600
    private static let stepAnimation: Animation = .easeOut(duration: 0.2)

    private var stepTransition: AnyTransition {
        let distance = Self.sheetWidth / 3
        let shift = stepTransitionDirection > 0 ? distance : -distance

        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: shift)),
            removal: .identity
        )
    }

    // MARK: - Navigation

    private var defaultFileDialogDirectory: URL? {
        try? FileManager.default.url(
            for: .desktopDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
    }

    var canProceedToNextStep: Bool {
        switch currentStep {
        case .method:
            return selectedMethod != nil
        case .configuration:
            switch selectedMethod {
            case .pull: return pull.isComplete
            case .build: return build.isComplete
            case .load: return load.isComplete
            case .none: return false
            }
        }
    }

    private func selectCreationMethod(_ method: CreationMethod) {
        selectedMethod = method
    }

    private func selectTarArchiveAndLoad() {
        failure = nil

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = load.tarFile?.parent ?? defaultFileDialogDirectory
        panel.allowedContentTypes = tarContentTypes

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        load.tarFile = url
        createImage()
    }

    private func prepareStepTransition() {
        shouldLoadPullFeaturedImages = false
    }

    private func completeStepTransition() {
        shouldLoadPullFeaturedImages = currentStep == .configuration && selectedMethod == .pull
    }

    func nextStep() {
        if selectedMethod == .load {
            selectTarArchiveAndLoad()
            return
        }

        guard let nextStep = Step(rawValue: currentStep.rawValue + 1) else {
            return
        }

        prepareStepTransition()
        stepTransitionDirection = 1
        paneTitle = paneTitle(for: nextStep)
        withAnimation(Self.stepAnimation) {
            currentStep = nextStep
            failure = nil
        } completion: {
            completeStepTransition()
        }
    }

    func previousStep() {
        // The failure stands in front of the step that produced it, so going
        // back leaves the failure rather than the step.
        guard failure == nil else {
            stepTransitionDirection = -1
            paneTitle = paneTitle(for: currentStep)
            withAnimation(Self.stepAnimation) {
                failure = nil
            }
            return
        }

        guard let previousStep = Step(rawValue: currentStep.rawValue - 1) else {
            return
        }
        prepareStepTransition()
        stepTransitionDirection = -1
        paneTitle = paneTitle(for: previousStep)
        withAnimation(Self.stepAnimation) {
            currentStep = previousStep
            failure = nil
        } completion: {
            completeStepTransition()
        }
    }

    // MARK: - Image Creation

    /// The sheet's part is settling what to make; making it belongs to the
    /// row it will land in, which is where it is watched and stopped.
    func createImage() {
        guard let method = selectedMethod else { return }

        do {
            switch method {
            case .pull:
                startPull()
            case .build:
                try startBuild()
            case .load:
                try startLoad()
            }
        } catch {
            // What is wrong with what was asked for is answered here, where
            // it can still be put right; what goes wrong doing it is answered
            // in the row.
            failure = ErrorAlert(
                failureTitle(for: method),
                error: error,
                showsDetails: false
            )

            return
        }

        dismiss()
    }

    /// Hands the build over to the row it will land in. The tag is settled
    /// here rather than left to the manager, so the row can be titled with
    /// what the image is going to be called.
    private func startBuild() throws {
        guard let contextDirectory = build.contextDirectory, let dockerFile = build.dockerFile else {
            throw ContainerizationError(
                .invalidArgument,
                message: "Choose a Dockerfile and the folder to build from."
            )
        }

        let tag = build.resolvedTag()
        let platform = build.targetPlatform
        let arguments = build.namedArguments
        let targetStage = build.targetStage
        let imageManager = imageManager

        activityCenter.start(
            id: ImageItem.identity(for: tag) ?? tag,
            kind: .image,
            title: tag,
            failureTitle: failureTitle(for: .build)
        ) { progress in
            try await imageManager.build(
                dockerFile: dockerFile,
                contextDirectory: contextDirectory,
                tag: tag,
                cpus: 2,
                memory: 1024.mib(),
                vSockPort: 8088,
                outputs: [
                    BuildImageOutputConfiguration(
                        type: .oci,
                        additionalFields: []
                    )
                ],
                platforms: [platform],
                buildArguments: arguments,
                labels: [],
                noCache: false,
                targetStage: targetStage,
                cacheIn: [],
                cacheOut: [],
                progress: progress
            )

            return nil
        }
    }

    /// Hands the load over to the row it will land in. What the archive holds
    /// is only known once it has been read, so the row is known by the file
    /// until then.
    private func startLoad() throws {
        guard let tarFile = load.tarFile else {
            throw ContainerizationError(
                .invalidArgument,
                message: "Choose the archive to load the image from."
            )
        }

        let force = load.force
        let imageManager = imageManager

        activityCenter.start(
            id: tarFile.path,
            kind: .image,
            title: tarFile.lastPathComponent,
            failureTitle: failureTitle(for: .load)
        ) { progress in
            let loaded = try await imageManager.load(
                tar: tarFile,
                force: force,
                progress: progress
            )

            // The archive says what it holds only once it has been read, and
            // what it holds is what the row has been standing in for.
            guard let reference = loaded.first?.reference else { return nil }

            return ImageItem.identity(for: reference) ?? reference
        }
    }

    /// Hands the pull over to the row it will land in, which is where it is
    /// watched and stopped from now on.
    private func startPull() {
        let reference = pull.reference
        let platform = pull.platform.platform
        let imageManager = imageManager

        activityCenter.start(
            id: ImageItem.identity(for: reference) ?? reference,
            kind: .image,
            title: reference,
            failureTitle: failureTitle(for: .pull)
        ) { progress in
            try await imageManager.pull(
                reference: reference,
                platform: platform,
                progress: progress
            )

            return nil
        }
    }

    private func failureTitle(for method: CreationMethod) -> String {
        switch method {
        case .pull:
            "The image couldn’t be pulled."
        case .build:
            "The image couldn’t be built."
        case .load:
            "The image couldn’t be loaded."
        }
    }
}
