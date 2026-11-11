//
//  NetworkSettingsView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/11/10.
//

import AppKit
import ContainersCore
import SwiftUI

struct NetworkSettingsView: View {
    @Environment(NetworkManager.self) private var networkManager
    @Environment(ContainerSystem.self) private var containerSystem

    @State private var errorAlert: ErrorAlert?
    @State private var systemMode = UserDefaults.systemMode ?? .default
    @State private var dnsDomains: [DNSDomainSetting] = []
    @State private var defaultDomain: String?
    @State private var selectedDomain: String?
    @State private var resolverDirectory: URL? = UserDefaults.resolverDirectory

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            NetworksSection()
            dnsDomainsSection
        }
        .task(refreshSettings)
        .errorAlert($errorAlert)
    }

    private var dnsDomainsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("DNS Domains")
                    .font(.headline)
                    .fontWeight(.semibold)

                Text(dnsDomainsDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)

            // Without the folder to read, there is no saying whether there are domains.
            SettingsList(
                items: domainChoices,
                emptyMessage: resolverDirectory == nil ? "DNS Domains Unavailable" : "No DNS Domains",
                selection: $selectedDomain
            ) { domain in
                HStack {
                    Text(domain.name)

                    Spacer(minLength: 12)

                    if domain.name == defaultDomain {
                        Text("Default")
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                if let selectedDomain, selectedDomain == defaultDomain {
                    Button("Don’t Use as Default", systemImage: "star.slash") {
                        setDefaultDomain(nil)
                    }
                    .help("Stop naming new containers in this domain")
                    .disabled(systemMode == .cliCompatibility)
                } else {
                    Button("Use as Default", systemImage: "star") {
                        setDefaultDomain(selectedDomain)
                    }
                    .help("Name new containers in this domain")
                    .disabled(systemMode == .cliCompatibility || selectedDomain == nil)
                }
            }

            if resolverDirectory == nil {
                SettingsWarning(
                    "Containers needs your permission to read the resolver files in /etc/resolver before it can show the domains kept there.",
                    actionTitle: "Allow Access…",
                    action: grantResolverAccess
                )
                .padding(.horizontal, 10)
            }
        }
        // The folder whose config.toml applies changes with container CLI compatibility.
        .task(id: systemMode) {
            defaultDomain = await containerSystem.configuration(in: UserDefaults.systemDataRoot).dnsDomain
        }
    }

    private var dnsDomainsDescription: String {
        let description = """
            Reach containers by name, such as web.test, and host services, such as host.containers.internal:8000. \
            Create a domain with “sudo container system dns create <domain>” in Terminal.
            """

        return systemMode == .cliCompatibility
            ? description + " The default domain is set in the container CLI’s config.toml."
            : description + " New containers are named in the default domain."
    }

    /// The resolver domains, and the default even without its resolver file, so it can still be unset.
    private var domainChoices: [DNSDomainSetting] {
        let names = dnsDomains.map(\.name)

        guard let defaultDomain, !names.contains(defaultDomain) else { return dnsDomains }

        return dnsDomains + [DNSDomainSetting(name: defaultDomain)]
    }

    private func setDefaultDomain(_ domain: String?) {
        Task {
            do {
                try await containerSystem.updateConfiguration(in: UserDefaults.systemDataRoot) { $0.dnsDomain = domain }
                defaultDomain = domain
            } catch {
                errorAlert = ErrorAlert("The default domain couldn’t be changed.", error: error)
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

        Task {
            guard let url = await panel.presentAsSheet() else { return }

            keepResolverDirectory(url)
        }
    }

    private func keepResolverDirectory(_ url: URL) {
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
            containerSystem.resolverDirectory = UserDefaults.resolverDirectory
            refreshSettings()
        } catch {
            errorAlert = ErrorAlert(
                "The resolver folder couldn’t be read.",
                error: error
            )
        }
    }

    private func refreshSettings() {
        systemMode = UserDefaults.systemMode ?? .default
        resolverDirectory = UserDefaults.resolverDirectory
        dnsDomains =
            resolverDirectory
            .map(networkManager.domains(in:))?
            .map(DNSDomainSetting.init(name:)) ?? []
    }
}

private struct DNSDomainSetting: Identifiable {
    var id: String { name }
    var name: String
}

extension URL {
    /// Whether this is the folder the resolver files are kept in, whichever
    /// way it was reached: `/etc` is a link to `/private/etc`, and an open
    /// panel answers with the latter.
    fileprivate var isResolverDirectory: Bool {
        isSameFolder(as: NetworkManager.resolverDirectory)
    }
}

#Preview {
    NetworkSettingsView()
        .environment(NetworkManager.preview)
        .environment(ContainerSystem.preview)
        .padding(24)
        .frame(width: 560)
}
