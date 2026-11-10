//
//  DashboardStatusBar.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import AppKit
import ContainersCore
import SwiftUI

/// The foot of the dashboard: the system's status, and what the containers
/// use between them.
struct DashboardStatusBar: View {
    @Environment(ContainerManager.self) private var containerManager
    @Environment(ContainerSystem.self) private var containerSystem

    @Binding var errorAlert: ErrorAlert?

    @SwiftUI.State private var usage = ResourceUsage.zero

    /// Each container's CPU time at the last reading, to measure the next by.
    @SwiftUI.State private var cpuSamples: [String: CPUSample] = [:]
    @SwiftUI.State private var lastDiskReading: Date = .distantPast

    private struct CPUSample {
        let usageMicroseconds: UInt64
        let date: Date
    }

    var body: some View {
        HStack(spacing: 16) {
            SystemStatusControl(errorAlert: $errorAlert)

            Divider()
                .frame(height: 16)

            HStack(spacing: 12) {
                if !containerSystem.isReadOnly {
                    reading("memorychip", String(format: "%.2f GB", usage.memoryUsage))
                    reading("cpu", String(format: "%.0f%%", usage.cpuUsage))
                }

                reading("internaldrive", String(format: "%.2f GB", usage.diskUsage))
            }
            .foregroundStyle(.secondary)

            Spacer()

            if showsTerminal {
                Button(action: openTerminal) {
                    Image(systemName: "apple.terminal.on.rectangle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Open Terminal")
                .padding(.trailing, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) {
            Divider()
        }
        .task {
            // TODO: Improve the 2-second polling.
            while !Task.isCancelled {
                await updateUsage()

                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// While the app manages the CLI's folder itself, the CLI is better left alone.
    private var showsTerminal: Bool {
        guard containerSystem.mode == .cliCompatibility else { return false }

        switch containerSystem.status {
        case .notStarted, .failed, .readOnly: return true
        case .starting, .running, .stopping: return false
        }
    }

    private func openTerminal() {
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }

        NSWorkspace.shared.openApplication(at: terminal, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard let error else { return }

            Task { @MainActor in
                errorAlert = ErrorAlert("Terminal couldn’t be opened.", error: error)
            }
        }
    }

    private func reading(_ symbol: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(value)
        }
        .font(.subheadline)
    }

    private func updateUsage() async {
        guard containerSystem.isRunning else {
            usage = .zero
            cpuSamples = [:]
            lastDiskReading = .distantPast

            return
        }

        let now = Date()
        let containers = await containerManager.resourceUsage()

        // Per container, so one stopping doesn't cancel out the rest; one that
        // restarted reads as zero for a reading.
        var cpuPercent = 0.0
        var samples: [String: CPUSample] = [:]

        for container in containers {
            let sample = CPUSample(
                usageMicroseconds: container.cpuUsageMicroseconds,
                date: now
            )

            if let previous = cpuSamples[container.id] {
                let elapsed = now.timeIntervalSince(previous.date)

                if elapsed > 0,
                    sample.usageMicroseconds >= previous.usageMicroseconds
                {
                    let spent = sample.usageMicroseconds - previous.usageMicroseconds

                    cpuPercent += Double(spent) / 1_000_000 / elapsed * 100
                }
            }

            samples[container.id] = sample
        }

        cpuSamples = samples

        // Heavier than asking the containers, so read every 30 seconds.
        var diskUsage = usage.diskUsage

        if now.timeIntervalSince(lastDiskReading) >= 30,
            let bytes = await containerSystem.diskUsage()
        {
            diskUsage = Double(bytes) / 1_000_000_000
            lastDiskReading = now
        }

        let memoryBytes = containers.reduce(UInt64(0)) { $0 + $1.memoryBytes }

        usage = ResourceUsage(
            memoryUsage: Double(memoryBytes) / 1_000_000_000,
            cpuUsage: cpuPercent,
            diskUsage: diskUsage
        )
    }
}
