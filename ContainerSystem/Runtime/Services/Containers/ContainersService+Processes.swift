//
//  ContainersService+Processes.swift
//  Containers
//
//  Running commands in, connecting to, and measuring running containers.
//
//  Created by Axel Martinez on 2026/10/24.
//

import Containerization
import ContainerizationError
import Foundation

extension ContainersService {
    /// What each running container is using right now. A container that
    /// cannot say, because it is on its way down, is left out.
    func resourceUsage() async -> [ContainerResourceUsage] {
        // Taken before the first await: the actor can change underneath it.
        let running = containers.compactMap { id, state in
            state.snapshot.status == .running
                ? state.container.map { (id, $0) } : nil
        }

        var usage: [ContainerResourceUsage] = []

        for (id, container) in running {
            guard
                let stats = try? await container.statistics(categories: [.memory, .cpu])
            else {
                continue
            }

            let entry = ContainerResourceUsage(
                id: id,
                memoryBytes: stats.memory?.usageBytes ?? 0,
                cpuUsageMicroseconds: stats.cpu?.usageUsec ?? 0
            )

            usage.append(entry)
        }

        return usage
    }

    /// Execute a command in a running container and return its output (uses vsock, no networking needed).
    func exec(id: String, arguments: [String]) async throws -> String {
        let container = try runningContainer(id: id)

        let outputURL = containerRoot.appendingPathComponent("\(id)-exec-output.tmp")

        FileManager.default.createFile(atPath: outputURL.path, contents: nil)

        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let writer = MultiWriter(handles: [outputHandle])

        let process = try await container.exec("exec-\(UUID().uuidString)") { config in
            config.arguments = arguments
            config.stdout = writer
            config.stderr = writer
        }

        try await process.start()

        let exitStatus = try await process.wait()

        try? writer.close()

        let output = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""

        try? FileManager.default.removeItem(at: outputURL)

        if exitStatus.exitCode != 0 {
            let message = "command failed with exit code \(exitStatus.exitCode): \(output)"
            throw ContainerizationError(.internalError, message: message)
        }

        return output
    }

    func dial(id: String, port: UInt32) async throws -> FileHandle {
        try await runningContainer(id: id).dialVsock(port: port)
    }
}
