//
//  ReportStore.swift
//  Containers
//
//  Created by Axel Martinez on 16/09/2026.
//

import Foundation

/// A manifest listing every report, plus one gzipped file per report body.
/// Listing reads only the manifest; bodies, which can run to megabytes, are read on demand.
actor ReportStore {
    private static let manifestFilename = "ReportStoreManifest.plist"
    private static let fileExtension = "activitylog"
    private static let formatVersion = 1

    private let root: URL
    private let manifestURL: URL

    private struct Manifest: Codable {
        let reportFormatVersion: Int
        var reports: [String: Record]

        init(
            reportFormatVersion: Int = ReportStore.formatVersion,
            reports: [String: Record] = [:]
        ) {
            self.reportFormatVersion = reportFormatVersion
            self.reports = reports
        }
    }

    private struct Record: Codable {
        let uniqueIdentifier: String
        let fileName: String
        let domainType: String
        let title: String
        let signature: String
        let timeStartedRecording: Double
        let timeStoppedRecording: Double
        let primaryObservable: Observable
        var hasBeenRead: Bool
    }

    private struct Observable: Codable {
        let highLevelStatus: String
        let totalNumberOfErrors: Int
        let totalNumberOfWarnings: Int
    }

    /// Safe to cache, since only this store writes the manifest.
    private var cached: Manifest?

    init(root: URL) throws {
        self.root = root
        self.manifestURL = root.appendingPathComponent(Self.manifestFilename)

        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
    }

    @discardableResult
    func record(
        level: Report.Level,
        kind: Report.Kind,
        name: String,
        message: String,
        body: String,
        startedAt: Date?
    ) throws -> Report {
        let endDate = Date()
        let date = startedAt ?? endDate
        let id = UUID().uuidString
        let fileName = "\(id).\(Self.fileExtension)"

        guard let deflated = Gzip.compressed(body) else {
            throw CocoaError(.fileWriteUnknown)
        }

        try deflated.write(
            to: root.appendingPathComponent(fileName),
            options: .atomic
        )

        let record = Record(
            uniqueIdentifier: id,
            fileName: fileName,
            domainType: kind.domainType,
            title: name,
            signature: message,
            timeStartedRecording: date.timeIntervalSinceReferenceDate,
            timeStoppedRecording: endDate.timeIntervalSinceReferenceDate,
            primaryObservable: Observable(
                highLevelStatus: level.status,
                totalNumberOfErrors: level == .error ? 1 : 0,
                totalNumberOfWarnings: level == .warning ? 1 : 0
            ),
            hasBeenRead: false
        )

        var manifest = self.manifest()
        manifest.reports[id] = record

        try write(manifest)

        return entry(for: record)
            ?? Report(
                id: id,
                date: date,
                endDate: endDate,
                level: level,
                kind: kind,
                name: name,
                message: message
            )
    }

    /// Most recent first.
    func list() -> [Report] {
        manifest().reports.values
            .compactMap(entry(for:))
            .sorted { $0.date > $1.date }
    }

    func entry(for id: String) -> Report? {
        manifest().reports[id].flatMap(entry(for:))
    }

    func body(of id: String) throws -> String {
        let data = try Data(contentsOf: url(for: id))

        guard let text = Gzip.text(of: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        return text
    }

    func markRead(_ ids: [String]) {
        var manifest = self.manifest()
        var changed = false

        for id in ids where manifest.reports[id]?.hasBeenRead == false {
            manifest.reports[id]?.hasBeenRead = true
            changed = true
        }

        guard changed else { return }

        try? write(manifest)
    }

    func remove(_ ids: [String]) {
        var manifest = self.manifest()

        for id in ids {
            manifest.reports.removeValue(forKey: id)

            try? FileManager.default.removeItem(at: url(for: id))
        }

        try? write(manifest)
    }

    nonisolated func url(for id: String) -> URL {
        root.appendingPathComponent("\(id).\(Self.fileExtension)")
    }

    /// An unreadable manifest is treated as empty, so new reports can still be written.
    private func manifest() -> Manifest {
        if let cached { return cached }

        guard let data = try? Data(contentsOf: manifestURL),
            let manifest = try? PropertyListDecoder().decode(
                Manifest.self,
                from: data
            )
        else {
            let empty = Manifest()
            cached = empty

            return empty
        }

        cached = manifest

        return manifest
    }

    private func write(_ manifest: Manifest) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml

        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        cached = manifest
    }

    private func entry(for record: Record) -> Report? {
        guard let kind = Report.Kind(domainType: record.domainType),
            let level = Report.Level(
                status: record.primaryObservable.highLevelStatus
            )
        else {
            return nil
        }

        return Report(
            id: record.uniqueIdentifier,
            date: Date(
                timeIntervalSinceReferenceDate: record.timeStartedRecording
            ),
            endDate: Date(
                timeIntervalSinceReferenceDate: record.timeStoppedRecording
            ),
            level: level,
            kind: kind,
            name: record.title,
            message: record.signature,
            isRead: record.hasBeenRead
        )
    }
}
