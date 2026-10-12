//
//  SystemStatusView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import ContainerSystem
import SwiftUI

struct SystemStatusView: View {
    @Environment(SystemManager.self) private var system

    var body: some View {
        switch system.status {
        case .starting:
            // What a first run has to install is reported on its own sheet,
            // so what is left to say here is that the system is starting.
            progress("Starting the container system…")
        case .stopping:
            progress("Stopping the container system…")
        case .failed:
            failedView
        case .notStarted:
            stoppedView
        case .running:
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
            Label(
                "The Container System Couldn’t Start",
                systemImage: "exclamationmark.triangle.fill"
            )
        } description: {
            if let error = system.startupError {
                Text(error.localizedDescription)
            }
        } actions: {
            Button("Try Again", action: start)
        }
    }

    private var stoppedView: some View {
        ContentUnavailableView {
            Label(
                "Container System Stopped",
                systemImage: SystemManager.Status.notStarted.symbol
            )
        } description: {
            Text("Start it to work with your containers, images and volumes.")
        } actions: {
            Button("Start", systemImage: "play.fill", action: start)
                .labelStyle(.titleAndIcon)
        }
    }

    private func start() {
        Task {
            // A failure puts the view into its own failed state, by way of
            // `system.startupError`.
            try? await system.start(appRoot: UserDefaults.applicationDataRoot)
        }
    }
}
