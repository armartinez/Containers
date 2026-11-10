//
//  BuildPipeline+Stdio.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/09.
//

import Foundation

extension BuildPipeline {
    func handleIO(_ io: IO, sender: AsyncStream<ClientStream>.Continuation, buildID: String) async throws {
        // Write the output to our terminal if not quiet
        if !config.quiet {
            if let handle = config.terminal?.handle {
                try handle.write(contentsOf: io.data)
            } else {
                // Fallback to stderr
                try FileHandle.standardError.write(contentsOf: io.data)
            }
        }

        // CRITICAL: Send terminal command response back to BuildKit
        // BuildKit waits for this response before continuing
        let cmdString = try TerminalCommand().json()
        var response = ClientStream()
        response.buildID = buildID
        response.command = .init()
        response.command.id = buildID
        response.command.command = cmdString
        sender.yield(response)
    }
}
