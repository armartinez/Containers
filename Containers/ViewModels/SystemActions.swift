//
//  SystemActions.swift
//  Containers
//
//  Created by Axel Martinez on 27/09/2026.
//

import AppKit
import ContainerSystem
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

    struct Failure: Error {
        let title: String
        let underlying: any Error
    }

    /// The action under way, if any.
    private(set) var working: Action?

    private let manager: SystemManager

    init(manager: SystemManager) {
        self.manager = manager
    }

    var isRunning: Bool {
        manager.status == .running
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
        let isSettled =
            working == nil && manager.status != .starting
            && manager.status != .stopping

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
                try await manager.stop()
            case .toggle:
                try await start()
            case .reload:
                try await manager.stop()
                try await start()
            case .quit:
                // Left running, the system would outlive the app.
                try? await manager.stop()
                NSApplication.shared.terminate(nil)
            }
        } catch {
            throw Failure(title: title, underlying: error)
        }
    }

    private func start() async throws {
        try await manager.start(appRoot: UserDefaults.applicationDataRoot)
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
