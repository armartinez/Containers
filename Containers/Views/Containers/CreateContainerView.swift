//
//  CreateContainerView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import ContainerSystem
import Containerization
import ContainerizationExtras
import ContainerizationOCI
import Foundation
import SwiftUI
import Virtualization

struct CreateContainerView: View {
    enum Mode {
        case create
        case run

        var title: String {
            switch self {
            case .create:
                "Create New Container"
            case .run:
                "Run Container"
            }
        }

        var progressTitle: String {
            switch self {
            case .create:
                "Creating container..."
            case .run:
                "Running container..."
            }
        }

        var buttonTitle: String {
            switch self {
            case .create:
                "Create"
            case .run:
                "Run"
            }
        }
    }

    enum Tab: String, CaseIterable, Identifiable {
        case info = "Info"
        case process = "Process"
        case options = "Options"

        var id: String { rawValue }
    }

    @Environment(ContainerManager.self) private var containerManager
    @Environment(ImageManager.self) private var imageManager
    @Environment(VolumeManager.self) private var volumeManager
    @Environment(ActivityCenter.self) private var activityCenter
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @SwiftUI.State var imageReference: String

    @SwiftUI.State private var process: ContainerProcess = .init()
    @SwiftUI.State private var options: ContainerManagementOptions = .init()
    @SwiftUI.State private var configuration: ContainerConfiguration = .init()
    @SwiftUI.State private var volumes: [VolumeMount] = []
    @SwiftUI.State private var mounts: [Mount] = []
    @SwiftUI.State private var ports: [PortMapping] = []
    @SwiftUI.State private var environments: [KeyValue] = []
    @SwiftUI.State private var registryScheme: String = RequestScheme.auto.rawValue
    @SwiftUI.State private var platformString: String = Platform.current.description
    @SwiftUI.State private var shmSize: String = ""
    @SwiftUI.State private var capabilities: [Capability] = []
    @SwiftUI.State private var errorAlert: ErrorAlert?
    @SwiftUI.State private var localImages: [ImageDescription] = []
    @SwiftUI.State private var availableVolumes: [Volume] = []
    @SwiftUI.State private var showProgressView: Bool = false
    @SwiftUI.State private var creationTask: Task<Void, Never>?
    @SwiftUI.State private var stepTransitionDirection: Int = 1
    @SwiftUI.State private var showStopConfirmation: Bool = false
    @SwiftUI.State private var showPickLocalImage: Bool = false

    // Tabs
    @SwiftUI.State private var selectedTab: Tab = .info
    @SwiftUI.State private var isVolumesExpanded = false
    @SwiftUI.State private var isMountsExpanded = false
    @SwiftUI.State private var isPortsExpanded = false
    @SwiftUI.State private var isCapabilitiesExpanded = false

    init(imageReference: String, mode: Mode = .create) {
        self.mode = mode
        self._imageReference = State(initialValue: imageReference)
    }

    var body: some View {
        CreateView(
            title: mode.title,
            error: $errorAlert,
            isProcessing: showProgressView,
            progressTitle: mode.progressTitle,
            width: Self.sheetWidth,
            height: 460,
            scrollsContent: selectedTab == .options,
            contentPadding: selectedTab == .info ? 20 : 0,
            contentID: showProgressView
                ? AnyHashable("progress") : AnyHashable(selectedTab),
            contentTransition: stepTransition,
            tabBar: {
                CreateViewTabBar(selection: $selectedTab)
            },
            content: {
                tabContent
            },
            actions: {
                Spacer()
                Button {
                    confirmStop()
                } label: {
                    Text("Cancel")
                        .frame(width: .sheetButtonLabelWidth)
                }
                .buttonStyle(.bordered)

                Button {
                    createContainer()
                } label: {
                    Text(mode.buttonTitle)
                        .frame(width: .sheetButtonLabelWidth)
                }
                .defaultAction(
                    enabled: !showProgressView
                        && !imageReference.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                )
            }
        )
        .sheet(
            isPresented: $showPickLocalImage,
            content: {
                ItemPicker(
                    title: "Choose Image",
                    actionTitle: "Choose",
                    items: self.localImages.map {
                        Item(id: $0.digest, label: $0.reference)
                    },
                    onSelect: { self.imageReference = $0.label }
                )
            }
        )
        .confirmationDialog(
            mode == .run ? "Stop Running Container" : "Stop Creating Container",
            isPresented: $showStopConfirmation,
            titleVisibility: .visible
        ) {
            Button("Stop", role: .destructive) {
                cancelCreation()
                dismiss()
            }

            Button("Continue", role: .cancel) {}
        } message: {
            Text(
                "The container hasn’t finished being \(mode == .run ? "started" : "created"). Stopping now discards it."
            )
        }
        .task {
            await preloadLocalImages()
            await preloadVolumes()
        }
        .onDisappear {
            self.showProgressView = false
        }
    }

    /// Work under way is only stopped on purpose, so the button asks first.
    private func confirmStop() {
        guard showProgressView else {
            dismiss()
            return
        }

        showStopConfirmation = true
    }

    private static var platformOptions: [String] {
        let current = Platform.current
        var options = [current.description]

        if current.architecture == "arm64" {
            options.append("linux/amd64")
        }

        return options
    }

    @ViewBuilder
    private var imageSelectionField: some View {
        if mode == .run {
            FormRow(title: "Image") {
                Text(imageReference)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } else {
            FormRow(title: "Image") {
                FormPicker(
                    placeholder: "Select Image...",
                    options: localImages.map { $0.reference },
                    selection: $imageReference,
                    actionTitle: "Other...",
                    onAction: { showPickLocalImage = true }
                )
            }
        }
    }

    private func preloadLocalImages() async {
        guard localImages.isEmpty else { return }

        localImages = (try? await imageManager.list().map(\.description)) ?? []

        if imageReference.isEmpty, let first = localImages.first {
            imageReference = first.reference
        }
    }

    private func showLocalImageSelection() {
        guard localImages.isEmpty else {
            showPickLocalImage = true
            return
        }

        Task {
            do {
                showProgressView = true
                localImages = try await imageManager.list().map(\.description)
                showProgressView = false
                showPickLocalImage = true
            } catch (let error) {
                showProgressView = false
                errorAlert = ErrorAlert(
                    "The images couldn’t be loaded.",
                    error: error
                )
            }
        }
    }

    /// Nested virtualization is refused outright by the Virtualization
    /// framework on hardware that cannot do it, so the flag is not offered
    /// where ticking it could only fail.
    private static let supportsNestedVirtualization =
        VZGenericPlatformConfiguration.isNestedVirtualizationSupported

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .info:
            infoTab
        case .process:
            processTab
        case .options:
            optionsTab
        }
    }

    private var infoTab: some View {
        FormStack {
            imageSelectionField

            FormRow(
                title: "Name",
                description:
                    "Leave empty to generate a unique name automatically. Names start with a letter or number, and may contain only letters, numbers, underscores, periods, and hyphens."
            ) {
                FormField(
                    placeholder: "my-container",
                    value: $options.name,
                    filter: EntityName.valid(from:)
                )
            }
        }
    }

    private var processTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            FormStack {
                FormRow(
                    title: "Entrypoint",
                    description: "Override the entrypoint of the image."
                ) {
                    FormField(
                        placeholder: "/bin/sh -c \"echo hello\"",
                        value: Binding(
                            get: { options.entryPoint ?? "" },
                            set: {
                                options.entryPoint = $0.isEmpty ? nil : $0
                            }
                        )
                    )
                }

                FormRow(title: "Stop Signal") {
                    FormField(
                        placeholder: "SIGTERM",
                        value: Binding(
                            get: { configuration.stopSignal ?? "" },
                            set: {
                                configuration.stopSignal =
                                    $0.trimmingCharacters(
                                        in: .whitespacesAndNewlines
                                    ).isEmpty ? nil : $0
                            }
                        )
                    )
                }
            }
            .padding(20)

            Divider()

            FormList(
                items: $environments,
                columnTitles: ["Environment Variables", "Value"],
                addLabel: "Add Environment Variable",
                emptyMessage: "No Environment Variables",
                newItem: { KeyValue() },
                rowFields: { keyValue in
                    [
                        .init(
                            placeholder: "Key",
                            text: keyValue.key,
                            isMonospaced: true
                        ),
                        .init(
                            placeholder: "Value",
                            text: keyValue.value,
                            isMonospaced: true
                        ),
                    ]
                }
            )
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    private var optionsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            FormStack {
                FormRow(
                    title: "Platform",
                    description:
                        "Choose the image variant to run. AMD64 containers use Rosetta on Apple Silicon."
                ) {
                    FormPicker(
                        placeholder: "Platform",
                        options: Self.platformOptions,
                        selection: $platformString
                    )
                }

                FormRow(
                    title: "Shared Memory",
                    description: "Size of /dev/shm (e.g. 64M, 1G)"
                ) {
                    FormField(
                        placeholder: "64M",
                        value: $shmSize
                    )
                }

                FormRow(title: "Management") {
                    VStack(alignment: .leading) {
                        Toggle(
                            "Remove the container after it stops",
                            isOn: $options.deleteOnTermination
                        )

                        Toggle(
                            "Mount the root filesystem as read-only",
                            isOn: $configuration.readOnly
                        )

                        Toggle(isOn: $configuration.virtualization) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(
                                    "Expose virtualization capabilities to the container"
                                )

                                Text(
                                    Self.supportsNestedVirtualization
                                        ? "Requires host and guest support."
                                        : "Nested virtualization needs an Apple silicon M3 chip or later."
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(!Self.supportsNestedVirtualization)

                        Toggle(
                            "Forward SSH agent socket to container",
                            isOn: $configuration.ssh
                        )
                    }
                    .toggleStyle(.checkbox)
                    .fieldProse()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            FormList(
                items: $volumes,
                title: "Volumes",
                isExpanded: $isVolumesExpanded,
                editorDescription:
                    "Select an existing volume or create an anonymous volume. To create a new named volume, use the Volumes section.",
                columnTitles: ["Source", "Target"],
                addLabel: "Add Volume",
                emptyMessage: "No Volumes",
                hasContentBelow: true,
                newItem: {
                    VolumeMount(
                        source: availableVolumes.isEmpty
                            ? .anonymousVolume : .volume,
                        volumeName: availableVolumes.last?.name ?? ""
                    )
                },
                rowSummary: \.summary,
                rowValues: \.columns,
                canSave: { !$0.trimmedTarget.isEmpty },
                editorContent: { $volume in
                    VolumeEditor(
                        mount: $volume,
                        availableVolumes: availableVolumes
                    )
                }
            )
            .padding(.horizontal)

            FormList(
                items: $mounts,
                title: "Mounts",
                isExpanded: $isMountsExpanded,
                editorDescription:
                    "Share a host path with the container, or tick Temporary mount to create an in-memory mount instead.",
                columnTitles: ["Source", "Target"],
                addLabel: "Add Mount",
                emptyMessage: "No Mounts",
                hasContentBelow: true,
                newItem: { Mount() },
                rowSummary: \.summary,
                rowValues: \.columns,
                canSave: {
                    !$0.trimmedTarget.isEmpty
                        && ($0.isTemporary || $0.hostURL != nil)
                },
                editorContent: { $mount in
                    MountEditor(mount: $mount)
                }
            )
            .padding(.horizontal)

            FormList(
                items: $ports,
                title: "Port Mappings",
                isExpanded: $isPortsExpanded,
                editorDescription:
                    "Publish a container port on the host, so it can be reached from outside the container.",
                columnTitles: ["Host", "Container", "Protocol"],
                addLabel: "Add Port Mapping",
                emptyMessage: "No Port Mappings",
                hasContentBelow: true,
                newItem: { PortMapping() },
                rowSummary: \.summary,
                rowValues: \.columns,
                editorContent: { $port in
                    PortEditor(port: $port)
                }
            )
            .padding(.horizontal)

            FormList(
                items: $capabilities,
                title: "Capabilities",
                isExpanded: $isCapabilitiesExpanded,
                columnTitles: ["Capability"],
                addLabel: "Add Capability",
                emptyMessage: "No Capabilities",
                newItem: { Capability() },
                rowFields: { $capability in
                    [
                        .init(
                            placeholder: "CAP_NET_ADMIN",
                            text: $capability.name
                        )
                    ]
                }
            )
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func preloadVolumes() async {
        guard availableVolumes.isEmpty else { return }
        availableVolumes = (try? await volumeManager.list()) ?? []
    }

    private static let sheetWidth: CGFloat = 660
    private static let stepAnimation: Animation = .easeOut(duration: 0.2)

    private var stepTransition: AnyTransition {
        let distance = Self.sheetWidth / 3
        let shift = stepTransitionDirection > 0 ? distance : -distance

        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: shift)),
            removal: .identity
        )
    }

    /// Stops work still in flight, so that closing the sheet leaves nothing
    /// running behind it.
    private func cancelCreation() {
        guard showProgressView else { return }

        creationTask?.cancel()
        creationTask = nil
        showProgressView = false
    }

    /// Hands the work over to the row it will appear in, which is where it is watched and stopped from now on.
    private func startCreation(
        imageReference: String,
        process: ContainerProcess,
        configuration: ContainerConfiguration,
        options: ContainerManagementOptions,
        registryScheme: String
    ) {
        let containerManager = containerManager
        let mode = mode
        let imagesDir = UserDefaults.applicationDataRoot
            .appendingPathComponent("images")

        activityCenter.start(
            id: options.name,
            kind: .container,
            title: options.name,
            subtitle: imageReference,
            failureTitle: mode == .run
                ? "The container couldn’t be started."
                : "The container couldn’t be created."
        ) { progress in
            func create(progress: Progress) async throws -> String {
                try await containerManager.create(
                    imageReference: imageReference,
                    imagesDir: imagesDir,
                    arguments: [],
                    process: process,
                    configuration: configuration,
                    options: options,
                    registryScheme: registryScheme,
                    progress: progress
                )
            }

            guard mode == .run else {
                _ = try await create(progress: progress)
                return nil
            }

            // Starting weighs as one of creating's six steps.
            progress.totalUnitCount = 7

            let containerID = try await progress.performStep(
                pendingUnitCount: 6
            ) { step in
                try await create(progress: step)
            }

            try await progress.performStep { step in
                _ = try await containerManager.run(
                    id: containerID,
                    progress: step
                )
            }

            return nil
        }
    }

    private func createContainer() {
        let trimmedReference = imageReference.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmedReference.isEmpty else {
            self.errorAlert = ErrorAlert(
                "The container needs an image.",
                message: "Choose the image to create the container from."
            )
            return
        }

        let trimmedShmSize = shmSize.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        var shmSizeInBytes: UInt64?

        if !trimmedShmSize.isEmpty {
            guard let bytes = try? Parser.memoryInBytes(from: trimmedShmSize)
            else {
                self.errorAlert = ErrorAlert(
                    "The shared memory size isn’t valid.",
                    message: "Enter a size such as 64M or 1G."
                )
                return
            }

            shmSizeInBytes = bytes
        }

        stepTransitionDirection = 1

        withAnimation(Self.stepAnimation) {
            self.showProgressView = true
        }

        creationTask = Task {
            do {
                let resolved = try ResolvedMounts(
                    mounts: self.mounts,
                    volumes: self.volumes
                )

                let existingVolumes = try await volumeManager.list()
                var volumes: [Volume] = []

                for request in resolved.volumes {
                    volumes.append(
                        try await volumeManager.volume(
                            named: request.name,
                            among: existingVolumes
                        )
                    )
                }

                self.configuration.mounts = resolved.filesystems(with: volumes)
                self.configuration.platform = try Platform(
                    from: self.platformString
                )
                self.configuration.shmSize = shmSizeInBytes
                self.configuration.capabilities = self.capabilities.names

                self.configuration.publishedPorts = self.ports.compactMap(
                    \.publishedPort
                )

                let validEnvironments = self.environments.filter({
                    !$0.key.trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                        && !$0.value.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        .isEmpty
                })

                self.process.environments = validEnvironments.map { kv in
                    "\(kv.key)=\(kv.value)"
                }

                // Make copies for actor boundary crossing
                let process = self.process
                let configuration = self.configuration
                var options = self.options
                let registryScheme = self.registryScheme
                // Settled here rather than left to the manager, so that the
                // row the work appears in can be titled with the name the
                // container is going to have.
                options.name = try ContainerManager.createContainerID(
                    name: options.name
                )

                startCreation(
                    imageReference: trimmedReference,
                    process: process,
                    configuration: configuration,
                    options: options,
                    registryScheme: registryScheme
                )

                dismiss()

                return
            } catch is CancellationError {
                // The sheet was closed on purpose; there is nothing to report.
            } catch (let error) {
                self.errorAlert = ErrorAlert(
                    mode == .run
                        ? "The container couldn’t be started."
                        : "The container couldn’t be created.",
                    error: error,
                    showsDetails: false
                )
            }

            self.stepTransitionDirection = -1

            withAnimation(Self.stepAnimation) {
                self.showProgressView = false
            }
        }
    }
}
