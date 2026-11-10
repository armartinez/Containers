//
//  SystemStatusView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import ContainersCore
import SwiftUI

struct SystemStatusView: View {
    @Environment(ContainerSystem.self) private var containerSystem
    @Environment(SystemActions.self) private var systemActions
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        switch containerSystem.status {
        case .starting:
            progress("Starting the container system…")
        case .stopping:
            progress("Stopping the container system…")
        case .failed:
            failedView
        case .notStarted:
            stoppedView
        case .running, .readOnly:
            EmptyView()
        }
    }

    /// Work under way is not missing content: it is a spinner and a line
    /// saying what is happening, not an unavailable-content view.
    private func progress(_ title: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)

            Text(title)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failedView: some View {
        ContentUnavailableView {
            Label("Container System Failed to Start", systemImage: "exclamationmark.triangle.fill")
                .lineLimit(1)
                .fixedSize()
        } description: {
            if let error = containerSystem.startupError {
                Text((error as? ContainerCLIError)?.message ?? error.localizedDescription)
            }
        } actions: {
            if isFixedInSettings {
                Button("Open Settings") {
                    openWindow(id: ContainersApp.settingsWindowID)
                }
            } else {
                Button("Try Again", action: start)
            }
        }
    }

    private var isFixedInSettings: Bool {
        (containerSystem.startupError as? ContainerCLIError)?.isFixedInSettings ?? false
    }

    private var stoppedView: some View {
        ContentUnavailableView {
            Label(
                "Container System Stopped",
                systemImage: ContainerSystem.Status.notStarted.symbol
            )
        } description: {
            Text("Your containers, images, and volumes appear here while the container system is running.")
        } actions: {
            Button("Start", systemImage: "play.fill", action: start)
                .labelStyle(.titleAndIcon)
        }
    }

    private func start() {
        Task {
            // A failure puts the view into its own failed state, by way of
            // `containerSystem.startupError`.
            try? await systemActions.startAskingForKernel()
        }
    }
}
