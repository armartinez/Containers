//
//  OSLogHandler.swift
//  ContainerSystem
//

import Logging
import os

struct OSLogHandler: LogHandler {
    private let osLogger: os.Logger
    public var logLevel: Logging.Logger.Level = .info
    private var formattedMetadata: String?

    public var metadata = Logging.Logger.Metadata() {
        didSet {
            formattedMetadata = Self.format(metadata)
        }
    }

    public subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    init(subsystem: String, category: String) {
        self.osLogger = os.Logger(subsystem: subsystem, category: category)
    }

    public func log(
        level: Logging.Logger.Level,
        message: Logging.Logger.Message,
        metadata: Logging.Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        var effective = formattedMetadata
        if let override = metadata, !override.isEmpty {
            effective = Self.format(self.metadata.merging(override) { $1 })
        }

        let text =
            effective.map { "\(message.description) \($0)" }
            ?? message.description

        osLogger.log(level: level.osLogType, "\(text, privacy: .public)")
    }

    private static func format(_ metadata: Logging.Logger.Metadata) -> String? {
        guard !metadata.isEmpty else { return nil }
        return metadata.map { "[\($0.key)=\($0.value)]" }.joined(separator: " ")
    }
}

extension Logging.Logger.Level {
    var osLogType: OSLogType {
        switch self {
        case .trace, .debug: return .debug
        case .info: return .info
        case .notice, .warning: return .default
        case .error: return .error
        case .critical: return .fault
        }
    }
}
