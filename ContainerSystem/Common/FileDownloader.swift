//
//  FileDownloader.swift
//  Containers
//
//  A download that says how far along it is, for what arrives over HTTP
//  rather than as an image.
//

import Foundation

/// Downloads a file to `destination`, reporting the bytes as they land.
///
/// The delegate takes delivery of the file itself. `URLSession`'s async
/// `download(from:)` and its completion-handler form both leave the progress
/// callbacks unsent, so a task with neither is the only one that reports.
final class FileDownloader: NSObject, URLSessionDownloadDelegate,
    @unchecked Sendable
{
    private let destination: URL
    private let progress: Progress
    private var continuation: CheckedContinuation<URLResponse, Error>?

    init(destination: URL, progress: Progress) {
        self.destination = destination
        self.progress = progress
    }

    func download(from url: URL) async throws -> URLResponse {
        let session = URLSession(
            configuration: .default,
            delegate: self,
            delegateQueue: nil
        )

        defer {
            session.finishTasksAndInvalidate()
        }

        let task = session.downloadTask(with: url)

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()

            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        progress.kind = .file
        progress.fileOperationKind = .downloading
        progress.totalUnitCount = totalBytesExpectedToWrite
        progress.completedUnitCount = totalBytesWritten
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.resume(returning: downloadTask.response ?? URLResponse())
        } catch {
            continuation?.resume(throwing: error)
        }

        continuation = nil
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }

        continuation?.resume(throwing: error)
        continuation = nil
    }
}
