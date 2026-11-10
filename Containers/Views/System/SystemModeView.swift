//
//  SystemModeView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/10/25.
//

import ContainersCore
import SwiftUI

/// Asks whether to turn on container CLI compatibility, the first time the dashboard opens without a mode
/// chosen.
struct SystemModeView: View {
    @Environment(ContainerSystem.self) private var containerSystem

    let onChoose: (ContainerSystem.Mode) -> Void

    @SwiftUI.State private var errorAlert: ErrorAlert?

    var body: some View {
        VStack(spacing: 24) {
            Image(.containerCLI)
                .resizable()
                .frame(width: 64, height: 64)

            VStack(spacing: 8) {
                Text("Turn On Container CLI Compatibility?")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(
                    """
                    If you use Apple’s container command-line tool, Containers can work with its containers, images \
                    and volumes. It needs a small script, which you’ll install next. You can change this later in \
                    Settings.
                    """
                )
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()

                Button {
                    onChoose(.default)
                } label: {
                    Text("Not Now")
                        .frame(minWidth: .sheetButtonLabelWidth)
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    turnOn()
                } label: {
                    Text("Turn On")
                        .frame(minWidth: .sheetButtonLabelWidth)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .padding(.bottom, 20)
        .frame(width: 494)
        // Nothing can start until there's an answer.
        .interactiveDismissDisabled()
        .errorAlert($errorAlert)
    }

    /// Compatibility needs the status script, so it's turned on only once the script is installed.
    private func turnOn() {
        guard !containerSystem.cli.isStatusScriptInstalled else {
            onChoose(.cliCompatibility)
            return
        }

        Task {
            do {
                guard try await StatusScriptInstaller.install(using: containerSystem) else { return }

                onChoose(.cliCompatibility)
            } catch {
                errorAlert = ErrorAlert("The script couldn’t be installed.", error: error)
            }
        }
    }
}

#Preview {
    SystemModeView(onChoose: { _ in })
        .environment(ContainerSystem.preview)
}
