//
//  ContainerCLI+AppRoot.swift
//  Containers
//
//  Created by Axel Martinez on 2026/11/05.
//

import Darwin
import Foundation

// What's known about the CLI and its folder from any isolation, without its status script.
nonisolated extension ContainerCLI {
    /// The folder the CLI uses unless it's started with `--app-root`, in the user's own home rather
    /// than the sandbox container that `FileManager` reports.
    public static let defaultAppRoot: URL = {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()

        return URL(filePath: home, directoryHint: .isDirectory).appending(
            path: "Library/Application Support/com.apple.container",
            directoryHint: .isDirectory
        )
    }()

    /// Releases checked to share the app's formats: the same containerization version, and the
    /// CLI's own stored types unchanged. Each new release is checked before it's added.
    static let supportedVersions: Set<String> = ["1.6.1"]

    /// Rewritten by the CLI's API server each time it starts.
    static let apiServerPlistPath = "apiserver/apiserver.plist"

    private static let defaultAppRootComponents = defaultAppRoot.resolvingSymlinksInPath().pathComponents

    /// Whether `folder` is the CLI's default folder, or one a CLI's API server has started on.
    public static func isAppRoot(_ folder: URL) -> Bool {
        folder.withSecurityScopedAccess {
            let resolved = folder.resolvingSymlinksInPath()

            return resolved.pathComponents == defaultAppRootComponents || hasAPIServerPlist(in: resolved)
        }
    }

    /// Whether `folder` is a CLI's folder, or lies inside one, which the app's own system can't use.
    ///
    /// Only the folders the sandbox lets the app look into can be told apart by the API server's plist;
    /// the default folder is known by its path.
    public static func owns(_ folder: URL) -> Bool {
        folder.withSecurityScopedAccess {
            // The ancestors of a resolved path hold no links, so they're checked without resolving again.
            var current = folder.resolvingSymlinksInPath()

            guard !current.pathComponents.starts(with: defaultAppRootComponents) else { return true }

            while current.pathComponents.count > 1 {
                if hasAPIServerPlist(in: current) {
                    return true
                }

                current.deleteLastPathComponent()
            }

            return false
        }
    }

    private static func hasAPIServerPlist(in folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appending(path: apiServerPlistPath).path(percentEncoded: false))
    }
}
