//
//  GeneralSettingsView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/11/10.
//

import AppKit
import ContainersCore
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(ContainerSystem.self) private var containerSystem

    @AppStorage(UserDefaults.appIconPlacementKey) private var appIconPlacement: AppIconPlacement = .dockAndMenuBar
    @AppStorage(UserDefaults.startsSystemOnOpenKey) private var startsSystemOnOpen = true

    @State private var errorAlert: ErrorAlert?
    @State private var loginItemStatus = SMAppService.mainApp.status
    @State private var storageLocation = UserDefaults.applicationDataRoot
    @State private var systemMode = UserDefaults.systemMode ?? .default
    @State private var hasCLIFolderAccess = UserDefaults.cliDataRoot != nil
    @State private var cliFolder = UserDefaults.cliDataRoot ?? ContainerCLI.defaultAppRoot

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            generalSection
            systemModeSection
            storageLocationSection
        }
        .task(refreshSettings)
        .errorAlert($errorAlert)
    }

    private var storageLocationPath: Binding<String> {
        Binding(
            get: { storageLocation.path },
            set: { _ in }
        )
    }

    /// Stopped, or read-only, where the system holds nothing a stop would lose.
    private var canChangeSystem: Bool {
        switch containerSystem.status {
        case .notStarted, .failed, .readOnly: true
        case .starting, .running, .stopping: false
        }
    }

    private var generalSection: some View {
        SettingsSection {
            settingRow("Open at login") {
                Toggle("Open at login", isOn: opensAtLogin)
            }

            if loginItemStatus == .requiresApproval {
                SettingsWarning(
                    "Containers needs your approval in System Settings to open at login.",
                    actionTitle: "Open Login Items…",
                    action: SMAppService.openSystemSettingsLoginItems
                )
            }

            settingRow("Show Containers in") {
                Picker("Show Containers in", selection: iconPlacement) {
                    ForEach(AppIconPlacement.allCases) { placement in
                        Text(placement.title)
                    }
                }
                .pickerStyle(.menu)
                .buttonStyle(.borderless)
                .fixedSize()
                .hoverHighlight()
            }

            settingRow("Start the container system when Containers opens") {
                Toggle("Start the container system when Containers opens", isOn: $startsSystemOnOpen)
            }
        }
    }

    private var opensAtLogin: Binding<Bool> {
        Binding(
            get: { loginItemStatus == .enabled || loginItemStatus == .requiresApproval },
            set: { isOn in
                do {
                    if isOn {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    errorAlert = ErrorAlert("The login item couldn’t be changed.", error: error)
                }

                loginItemStatus = SMAppService.mainApp.status
            }
        )
    }

    private var iconPlacement: Binding<AppIconPlacement> {
        Binding(
            get: { appIconPlacement },
            set: { placement in
                appIconPlacement = placement
                NSApp.updateActivationPolicy()
            }
        )
    }

    /// A title with its control on the trailing side, as System Settings lays out a row.
    private func settingRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(title)

            Spacer(minLength: 12)

            control()
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }

    private var systemModeSection: some View {
        SettingsSection(title: "Compatibility") {
            HStack(alignment: .top, spacing: 10) {
                Image(.containerCLI)
                    .resizable()
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Container CLI compatibility")

                    // The help article this links to is still to be written.
                    Text(
                        """
                        Work with the containers, images and volumes of Apple’s container CLI, in its own folder. \
                        [Learn more…](https://try-containers.github.io/documentation/containers/usingthecontainercli)
                        """
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Toggle("Container CLI compatibility", isOn: isCLICompatible)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .disabled(!canChangeSystem)
            }

        }
        .task {
            if systemMode == .cliCompatibility, !containerSystem.cli.isStatusScriptInstalled {
                installStatusScript()
            }
        }
        .onChange(of: systemMode) { previous, mode in
            guard mode != UserDefaults.systemMode else { return }

            switch mode {
            case .cliCompatibility:
                switchToCLICompatibility(from: previous)
            case .default:
                commitSystemMode(mode)
            }
        }
    }

    private var isCLICompatible: Binding<Bool> {
        Binding(
            get: { systemMode == .cliCompatibility },
            set: { isOn in
                // The status script comes first.
                if isOn, !containerSystem.cli.isStatusScriptInstalled {
                    installStatusScript()
                } else {
                    systemMode = isOn ? .cliCompatibility : .default
                }
            }
        )
    }

    private func installStatusScript() {
        Task {
            do {
                guard try await StatusScriptInstaller.install(using: containerSystem) else { return }

                // Already on, as after an update that changes the script, the system restarts to use it.
                if systemMode == .cliCompatibility {
                    commitSystemMode(.cliCompatibility)
                } else {
                    systemMode = .cliCompatibility
                }
            } catch {
                errorAlert = ErrorAlert("The script couldn’t be installed.", error: error)
            }
        }
    }

    private func switchToCLICompatibility(from previous: ContainerSystem.Mode) {
        Task {
            do {
                try await containerSystem.cli.requireInstalled()
                commitSystemMode(.cliCompatibility)
            } catch {
                systemMode = previous
                errorAlert = ErrorAlert("Container CLI compatibility can’t be turned on.", error: error)
            }
        }
    }

    /// Starts again in the new mode, so the dashboard shows what the mode does at once, unless the user
    /// stopped the system. The mode only changes while nothing of the app's own is running.
    private func commitSystemMode(_ mode: ContainerSystem.Mode) {
        let wasStoppedByUser = containerSystem.status == .notStarted && !containerSystem.needsKernelConfirmation

        UserDefaults.systemMode = mode
        containerSystem.mode = mode

        guard !wasStoppedByUser else {
            containerSystem.watchForAPIServer(in: UserDefaults.systemDataRoot)
            return
        }

        Task {
            try? await containerSystem.stop()
            // Failures show on the dashboard; a missing kernel is asked about when the user starts it.
            try? await containerSystem.start(appRoot: UserDefaults.systemDataRoot)
        }
    }

    private var storageLocationSection: some View {
        SettingsSection(title: "Storage") {
            switch systemMode {
            case .default:
                SettingsRow(
                    description: """
                        Containers, images, volumes, kernels, and build data are stored in this folder.
                        Changes take effect the next time the container system starts.
                        """
                ) {
                    FormField(
                        placeholder: "Storage location",
                        value: storageLocationPath,
                        isEditable: false,
                        actionIcon: "folder",
                        actionTitle: "Choose",
                        action: chooseStorageLocation
                    )
                    .disabled(!canChangeSystem)
                }

                HStack {
                    Spacer()

                    Button("Use Default", action: resetStorageLocation)
                        .disabled(!canChangeSystem || UserDefaults.usesDefaultApplicationDataRoot)
                }
            case .cliCompatibility:
                SettingsRow(
                    description: "With container CLI compatibility on, Containers uses the container CLI’s folder."
                ) {
                    FormField(
                        placeholder: "Container CLI folder",
                        value: .constant(cliFolder.path),
                        isEditable: false
                    )
                }

                if !hasCLIFolderAccess {
                    SettingsWarning(
                        "Containers needs your permission to read the container CLI’s folder.",
                        actionTitle: "Allow Access…",
                        action: allowCLIFolderAccess
                    )
                }
            }
        }
    }

    private func refreshSettings() {
        storageLocation = UserDefaults.applicationDataRoot
        systemMode = UserDefaults.systemMode ?? .default
        hasCLIFolderAccess = UserDefaults.cliDataRoot != nil
        loginItemStatus = SMAppService.mainApp.status
        cliFolder = UserDefaults.cliDataRoot ?? ContainerCLI.defaultAppRoot
    }

    private func chooseStorageLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = storageLocation
        panel.prompt = "Choose"
        panel.message =
            "Choose where Containers stores containers, images, volumes, kernels, and build data."

        Task {
            guard let url = await panel.presentAsSheet() else { return }

            keepStorageLocation(url)
        }
    }

    private func keepStorageLocation(_ url: URL) {
        guard !ContainerCLI.owns(url) else {
            errorAlert = ErrorAlert(
                "That folder belongs to the container CLI.",
                message: "To work with the container CLI’s containers, images and volumes, turn on container CLI compatibility."
            )

            return
        }

        setStorageLocation(url)
    }

    private func allowCLIFolderAccess() {
        Task {
            // A running API server says which folder it uses, which may be one given with --app-root.
            let runningFolder = await containerSystem.cli.runningAppRoot()

            guard let url = await chooseCLIFolder(prompt: "Allow", startingAt: runningFolder) else { return }

            grantCLIFolderAccess(url)
        }
    }

    private func grantCLIFolderAccess(_ url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)

            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            UserDefaults.setCLIDataRoot(bookmarkData: bookmarkData)
            hasCLIFolderAccess = true
            cliFolder = url
            restartIfReadOnly()
        } catch {
            errorAlert = ErrorAlert("The container CLI’s folder couldn’t be opened.", error: error)
        }
    }

    /// The sandbox lets the app into the CLI's folder only once the user picks it, so this asks
    /// for it in an open panel, as Choose does.
    private func chooseCLIFolder(prompt: String, startingAt runningFolder: URL?) async -> URL? {
        let cliAppRoot = runningFolder ?? cliFolder
        let exists = FileManager.default.fileExists(atPath: cliAppRoot.path)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        // A folder the CLI hasn't made yet is made from its parent.
        panel.directoryURL = exists ? cliAppRoot : cliAppRoot.deletingLastPathComponent()
        panel.prompt = prompt
        panel.message =
            exists
            ? "Choose the container CLI’s folder, so Containers can share its containers, images and volumes."
            : "Create a folder named “\(cliAppRoot.lastPathComponent)” here, where the container CLI keeps its data, and choose it."

        guard let url = await panel.presentAsSheet() else {
            return nil
        }

        guard ContainerCLI.isAppRoot(url) else {
            errorAlert = ErrorAlert(
                "That isn’t a container CLI folder.",
                message: """
                    Choose the container CLI’s default folder, \(ContainerCLI.defaultAppRoot.path), or the one you start it with \
                    using --app-root. Another folder counts once the CLI has started in it.
                    """
            )

            return nil
        }

        return url
    }

    private func setStorageLocation(_ url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
            UserDefaults.setApplicationDataRoot(url, bookmarkData: bookmarkData)
            storageLocation = UserDefaults.applicationDataRoot
            restartIfReadOnly()
        } catch {
            errorAlert = ErrorAlert(
                "The storage location couldn’t be changed.",
                error: error
            )
        }
    }

    private func resetStorageLocation() {
        UserDefaults.resetApplicationDataRoot()
        storageLocation = UserDefaults.applicationDataRoot
        restartIfReadOnly()
    }

    /// Read-only, the system holds nothing a stop would lose, so it takes a change of
    /// mode or folder at once rather than at its next start.
    private func restartIfReadOnly() {
        let wasRefused = containerSystem.startupError is ContainerCLIError

        guard containerSystem.isReadOnly || wasRefused else { return }

        Task {
            do {
                try await containerSystem.stop()
                try await containerSystem.start(appRoot: UserDefaults.systemDataRoot)
            } catch  where wasRefused {
            } catch {
                errorAlert = ErrorAlert("The container system couldn’t restart.", error: error)
            }
        }
    }
}

#Preview {
    GeneralSettingsView()
        .environment(ContainerSystem.preview)
        .padding(24)
        .frame(width: 560)
}
