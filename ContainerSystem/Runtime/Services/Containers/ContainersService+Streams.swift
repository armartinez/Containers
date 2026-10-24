//
//  ContainersService+Streams.swift
//  Containers
//
//  The stdio plumbing between containers and files, and waiting on a container to exit.
//
//  Created by Axel Martinez on 2026/10/24.
//

import Containerization
import Foundation

extension ContainersService {
    struct MultiWriter: Writer {
        let handles: [FileHandle]

        func close() throws {
            for handle in handles {
                try handle.close()
            }
        }

        func write(_ data: Data) throws {
            for handle in handles {
                try handle.write(contentsOf: data)
            }
        }
    }

    /// Answers a wait once, with whichever comes first: the container's exit, or the caller giving up on it.
    final class ExitWaiter: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Int32, Error>?
        private var answered = false

        func wait(for monitor: Task<Int32, Never>) async throws -> Int32 {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    lock.lock()

                    // Cancelled before the wait even began.
                    guard !answered else {
                        lock.unlock()
                        continuation.resume(throwing: CancellationError())
                        return
                    }

                    self.continuation = continuation

                    lock.unlock()

                    Task {
                        let exitCode = await monitor.value
                        self.answer(with: .success(exitCode))
                    }
                }
            } onCancel: {
                answer(with: .failure(CancellationError()))
            }
        }

        private func answer(with result: Result<Int32, Error>) {
            lock.lock()

            guard !answered else {
                lock.unlock()
                return
            }

            answered = true
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()

            continuation?.resume(with: result)
        }
    }

    struct FileHandleReader: ReaderStream {
        let handle: FileHandle

        func stream() -> AsyncStream<Data> {
            .init { cont in
                self.handle.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        handle.readabilityHandler = nil
                        cont.finish()
                        return
                    }
                    cont.yield(data)
                }
            }
        }
    }
}
