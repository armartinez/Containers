//
//  GeneralSettingsView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/11/10.
//

import AppKit
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(UserDefaults.appIconPlacementKey) private var appIconPlacement: AppIconPlacement = .dockAndMenuBar
    @AppStorage(UserDefaults.startsSystemOnOpenKey) private var startsSystemOnOpen = true

    @State private var errorAlert: ErrorAlert?
    @State private var loginItemStatus = SMAppService.mainApp.status

    var body: some View {
        generalSection
            .task(refreshSettings)
            .errorAlert($errorAlert)
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

    private func refreshSettings() {
        loginItemStatus = SMAppService.mainApp.status
    }
}

#Preview {
    GeneralSettingsView()
        .padding(24)
        .frame(width: 560)
}
