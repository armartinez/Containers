//
//  FolderEvents.swift
//  Containers
//
//  Reports changes under a folder as they happen, from FSEvents.
//
//  Created by Axel Martinez on 2026/10/25.
//

import CoreServices
import Foundation

/// The changes FSEvents reports under a folder, made by any process.
enum FolderEvents {
    /// Yields the paths that changed under `folder`, relative to it, in batches FSEvents gathers
    /// over `latency` seconds. Ends watching when the stream's consumer goes away.
    static func changes(under folder: URL, latency: TimeInterval = 0.3) -> AsyncStream<[String]> {
        // FSEvents reports real paths: `/var` comes back as `/private/var`, which
        // `resolvingSymlinksInPath()` would strip again.
        let path = folder.path(percentEncoded: false)
        let root =
            realpath(path, nil).map { resolved in
                defer { free(resolved) }
                return String(cString: resolved)
            } ?? path
        let prefix = root.hasSuffix("/") ? root : root + "/"

        return AsyncStream { continuation in
            let receiver = Receiver(prefix: prefix, continuation: continuation)
            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passRetained(receiver).toOpaque(),
                retain: nil,
                release: { info in
                    guard let info else { return }
                    Unmanaged<Receiver>.fromOpaque(info).release()
                },
                copyDescription: nil
            )
            let flags = FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot
            )

            guard
                let stream = FSEventStreamCreate(
                    nil,
                    { _, info, _, paths, _, _ in
                        guard let info else { return }

                        let receiver = Unmanaged<Receiver>.fromOpaque(info).takeUnretainedValue()
                        let paths = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []

                        receiver.receive(paths)
                    },
                    &context,
                    [root] as CFArray,
                    FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                    latency,
                    flags
                )
            else {
                continuation.finish()
                return
            }

            let handle = StreamHandle(stream: stream)

            FSEventStreamSetDispatchQueue(stream, DispatchQueue(label: "app.containers.folder-events"))
            FSEventStreamStart(stream)

            continuation.onTermination = { _ in
                handle.invalidate()
            }
        }
    }

    /// Hands the callback's paths to the stream, from the stream's own queue.
    private final class Receiver: Sendable {
        let prefix: String
        let continuation: AsyncStream<[String]>.Continuation

        init(prefix: String, continuation: AsyncStream<[String]>.Continuation) {
            self.prefix = prefix
            self.continuation = continuation
        }

        func receive(_ paths: [String]) {
            let relativePaths = paths.compactMap { path in
                path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : nil
            }

            guard !relativePaths.isEmpty else { return }

            continuation.yield(relativePaths)
        }
    }

    /// `@unchecked Sendable`: the stream is only touched again once, to stop it, after which it's
    /// released and never used.
    private final class StreamHandle: @unchecked Sendable {
        private let stream: FSEventStreamRef

        init(stream: FSEventStreamRef) {
            self.stream = stream
        }

        func invalidate() {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
