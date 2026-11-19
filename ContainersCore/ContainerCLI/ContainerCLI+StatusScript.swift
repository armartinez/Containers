//
//  ContainerCLI+StatusScript.swift
//  Containers
//
//  Created by Axel Martinez on 2026/11/05.
//

import Foundation

extension ContainerCLI {
    /// Asks the CLI for its version and status from outside the sandbox, as a user script.
    public enum StatusScript {
        static let name = "container-status"

        /// Where the script has to be installed for the app to run it.
        public static var url: URL? {
            let folder = try? FileManager.default.url(
                for: .applicationScriptsDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )

            return folder?.appending(path: name, directoryHint: .notDirectory)
        }

        static var isInstalled: Bool {
            guard let url else { return false }

            return (try? String(contentsOf: url, encoding: .utf8)) == source
                && FileManager.default.isExecutableFile(atPath: url.path(percentEncoded: false))
        }

        static var isOutdated: Bool {
            guard let url else { return false }

            return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) && !isInstalled
        }

        /// Runs the script, and reads the CLI's status from what it prints.
        static func run() async throws -> Status {
            guard let url else {
                throw CocoaError(.fileNoSuchFile)
            }

            let task = try NSUserUnixTask(url: url)
            let output = Pipe()

            task.standardOutput = output.fileHandleForWriting

            try await task.execute(withArguments: nil)
            try output.fileHandleForWriting.close()

            return try Status(output: output.fileHandleForReading.readToEnd() ?? Data())
        }

        static let source = """
            #!/bin/sh
            # Asks Apple's container CLI for its version and status, for the Containers app.

            PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"

            if ! command -v container >/dev/null 2>&1; then
                echo '{"versions":[],"status":{"status":"notInstalled"}}'
                exit 0
            fi

            versions=$(container system version --format json 2>/dev/null)
            status=$(container system status --format json 2>/dev/null)

            printf '{"versions":%s,"status":%s}\\n' "${versions:-[]}" "${status:-null}"

            """
    }
}
