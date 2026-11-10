//
//  SystemActions.swift
//  Containers
//
//  Created by Axel Martinez on 27/09/2026.
//

import AppKit
import ContainersCore
import Foundation
import Observation

/// What can be asked of the container system.
@Observable
@MainActor
final class SystemActions {
    enum Action {
        case toggle
        case reload
        case quit
    }

    /// The container CLI runs over the system's folder, which the system can't manage until the CLI stops.
    struct CLIRunningError: LocalizedError {
        var errorDescription: String? {
            "Stop it with “container system stop” first, then start the container system to manage its containers, images and volumes here."
        }
    }

    struct Failure: Error {
        let title: String
        let underlying: any Error
    }

    /// The action under way, if any.
    private(set) var working: Action?

    /// Whether a start the user asked for is waiting for them to agree to download the kernel.
    private(set) var isAskingForKernel = false

    private let containerSystem: ContainerSystem

    init(containerSystem: ContainerSystem) {
        self.containerSystem = containerSystem
    }

    /// Beside a running CLI the system only reads its folder, so the toggle offers to start it in full.
    private var isRunning: Bool {
        containerSystem.status == .running
    }

    func title(for action: Action) -> String {
        switch action {
        case .toggle: isRunning ? "Stop" : "Start"
        case .reload: "Reload"
        case .quit: "Quit"
        }
    }

    func symbol(for action: Action) -> String {
        switch action {
        case .toggle: isRunning ? "stop" : "play.fill"
        case .reload: "arrow.clockwise"
        case .quit: "power"
        }
    }

    func isEnabled(_ action: Action) -> Bool {
        let isSettled = working == nil && containerSystem.status != .starting && containerSystem.status != .stopping

        switch action {
        case .toggle: return isSettled
        case .reload: return isSettled && isRunning
        case .quit: return working == nil
        }
    }

    func perform(_ action: Action) async throws(Failure) {
        let title = failureTitle(for: action)
        working = action

        defer { working = nil }

        do {
            switch action {
            case .toggle where isRunning:
                try await containerSystem.stop()
            case .toggle:
                // With compatibility on, the CLI has to be stopped before the system can manage its folder.
                if containerSystem.mode == .cliCompatibility, await containerSystem.cli.isRunning() {
                    throw CLIRunningError()
                }

                if containerSystem.isReadOnly {
                    try await containerSystem.stop()
                }

                try await startAskingForKernel()
            case .reload:
                try await containerSystem.stop()
                try await startAskingForKernel()
            case .quit:
                // Left running, the system would outlive the app.
                try? await containerSystem.stop()
                NSApplication.shared.terminate(nil)
            }
        } catch let error as CLIRunningError {
            throw Failure(title: "The container CLI is running.", underlying: error)
        } catch {
            throw Failure(title: title, underlying: error)
        }
    }

    /// Starts the system as the user asks, and asks about the kernel instead if it's missing.
    func startAskingForKernel() async throws {
        // Tried every time: with compatibility on, a CLI that started since only needs its folder read.
        do {
            try await containerSystem.start(appRoot: UserDefaults.systemDataRoot)
        } catch ContainerSystem.SetupError.kernelInstallNotConfirmed {}

        if containerSystem.needsKernelConfirmation {
            isAskingForKernel = true
        }
    }

    func dismissKernelQuestion() {
        isAskingForKernel = false
    }

    private func failureTitle(for action: Action) -> String {
        switch action {
        case .toggle where isRunning: "The container system couldn’t stop."
        case .toggle: "The container system couldn’t start."
        case .reload: "The container system couldn’t reload."
        case .quit: "The container system couldn’t stop."
        }
    }
}
