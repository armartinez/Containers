//
//  SettingsView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import AppKit
import ContainerSystem
import SwiftUI

struct SettingsView: View {
    @Environment(NetworkManager.self) private var networkManager
    @Environment(SystemManager.self) private var system

    @State private var errorAlert: ErrorAlert?
    @State private var storageLocation = UserDefaults.applicationDataRoot
    @State private var dnsDomains: [DNSDomainSetting] = []
    @State private var resolverDirectory: URL? = UserDefaults.resolverDirectory
    @State private var selectedSection: SettingsPane? = .general
    @State private var sectionHistory: [SettingsPane] = [.general]
    @State private var sectionHistoryIndex = 0

    private var activeSection: SettingsPane {
        selectedSection ?? .general
    }

    private var canNavigateBack: Bool {
        sectionHistoryIndex > 0
    }

    private var canNavigateForward: Bool {
        sectionHistoryIndex < sectionHistory.count - 1
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selectedSection) {
                section in
                NavigationLink(value: section) {
                    SidebarRow(section: section)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 230, ideal: 230, max: 230)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            content
                .navigationTitle(activeSection.title)
                .toolbarTitleDisplayMode(.inlineLarge)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: navigateBack) {
                    Image(systemName: "chevron.left")
                }
                .help("Back")
                .disabled(!canNavigateBack)

                Button(action: navigateForward) {
                    Image(systemName: "chevron.right")
                }
                .help("Forward")
                .disabled(!canNavigateForward)
            }
        }
        .frame(width: 760, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            refreshSettings()
        }
        .errorAlert($errorAlert)
        .onChange(of: selectedSection) { oldValue, newValue in
            guard let newValue, newValue != oldValue else {
                return
            }

            recordSectionNavigation(to: newValue)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch activeSection {
        case .general:
            generalSettingsContent
        case .network:
            networkSettingsContent
        }
    }

    private var generalSettingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                storageLocationSection
            }
            .frame(maxWidth: 520, alignment: .topLeading)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var networkSettingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                dnsDomainsSection
            }
            .frame(maxWidth: 520, alignment: .topLeading)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var storageLocationPath: Binding<String> {
        Binding(
            get: { storageLocation.path },
            set: { _ in }
        )
    }

    private var storageLocationSection: some View {
        SettingsSection(title: "Storage") {
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
                .disabled(system.status == .running)
            }

            HStack {
                Spacer()

                Button("Use Default", action: resetStorageLocation)
                    .disabled(system.status == .running || UserDefaults.usesDefaultApplicationDataRoot)
            }
        }
    }

    private var dnsDomainsSection: some View {
        SettingsSection(title: "DNS Domains") {
            SettingsRow(
                description:
                    "DNS domains let containers access host services, such as host.containers.internal:8000. Manage domains by creating resolver files in /etc/resolver/."
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    // Without the folder to read, there is no saying whether
                    // there are domains: the warning below asks for it rather
                    // than this claiming there are none.
                    if resolverDirectory == nil {
                        Text("Domains unavailable")
                            .foregroundStyle(.secondary)
                    } else if dnsDomains.isEmpty {
                        Text("No domains configured")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(dnsDomains) { domain in
                            Text(domain.name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    Color(nsColor: .controlBackgroundColor),
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                        }
                    }
                }
            }

            if resolverDirectory == nil {
                SettingsWarning(
                    "Containers needs your permission to read the resolver files in /etc/resolver before it can show the domains kept there.",
                    actionTitle: "Allow Access…",
                    action: grantResolverAccess
                )
            }
        }
    }

    /// The folder is the user's to give, and an open panel is how they give
    /// it: what comes back is kept as a bookmark, which is what the app reads
    /// through on every later launch.
    private func grantResolverAccess() {
        let directory = NetworkManager.resolverDirectory
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = directory
        panel.prompt = "Allow"
        panel.message =
            "Choose the /etc/resolver folder, so Containers can read the DNS domains the container CLI keeps in it."

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        guard url.isResolverDirectory else {
            errorAlert = ErrorAlert(
                "That isn’t the resolver folder.",
                message:
                    "Containers reads its DNS domains from /etc/resolver. Choose that folder to show them here."
            )

            return
        }

        do {
            let bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            UserDefaults.setResolverDirectory(bookmarkData: bookmarkData)
            refreshSettings()
        } catch {
            errorAlert = ErrorAlert(
                "The resolver folder couldn’t be read.",
                error: error
            )
        }
    }

    private func navigateBack() {
        guard canNavigateBack else {
            return
        }

        sectionHistoryIndex -= 1
        selectedSection = sectionHistory[sectionHistoryIndex]
    }

    private func navigateForward() {
        guard canNavigateForward else {
            return
        }

        sectionHistoryIndex += 1
        selectedSection = sectionHistory[sectionHistoryIndex]
    }

    private func recordSectionNavigation(to section: SettingsPane) {
        guard sectionHistory.indices.contains(sectionHistoryIndex),
            sectionHistory[sectionHistoryIndex] != section
        else {
            return
        }

        if canNavigateForward {
            sectionHistory = Array(
                sectionHistory.prefix(sectionHistoryIndex + 1)
            )
        }

        sectionHistory.append(section)
        sectionHistoryIndex = sectionHistory.count - 1
    }

    private func refreshSettings() {
        storageLocation = UserDefaults.applicationDataRoot
        resolverDirectory = UserDefaults.resolverDirectory
        dnsDomains =
            resolverDirectory
            .map(networkManager.listDomains(in:))?
            .map(DNSDomainSetting.init(name:)) ?? []
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

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

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
    }
}

private struct SidebarRow: View {
    let section: SettingsPane

    var body: some View {
        Label {
            Text(section.title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: section.icon)
                .font(.system(size: 13, weight: .medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case network

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .network: "Network"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape.fill"
        case .network: "network"
        }
    }
}

private struct DNSDomainSetting: Identifiable {
    let id = UUID()
    var name: String
}

private struct SettingsWarning: View {
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        _ message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Spacer(minLength: 8)

                Button(actionTitle, action: action)
                    .controlSize(.small)
                    .fixedSize()
            }
        }
    }
}

extension URL {
    /// Whether this is the folder the resolver files are kept in, whichever
    /// way it was reached: `/etc` is a link to `/private/etc`, and an open
    /// panel answers with the latter.
    fileprivate var isResolverDirectory: Bool {
        resolvingSymlinksInPath().standardizedFileURL
            == NetworkManager.resolverDirectory
            .resolvingSymlinksInPath().standardizedFileURL
    }
}

#Preview {
    SettingsView()
        .environment(NetworkManager())
        .environment(SystemManager())
}
