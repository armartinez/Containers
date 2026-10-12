//
//  BuildPipeline+FSSync.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/09.
//

import ContainerizationArchive
import ContainerizationOS
import CryptoKit
import Foundation

extension BuildPipeline {
    func handleFSSyncTransfer(
        _ buildTransfer: BuildTransfer,
        sender: AsyncStream<ClientStream>.Continuation,
        buildID: String
    ) async throws {
        guard let method = buildTransfer.metadata["method"] else {
            logger.error("BuildTransfer missing method")
            return
        }

        let contextDir = URL(fileURLWithPath: config.contextDir)

        switch method {
        case "Read":
            try await handleFSSyncRead(
                buildTransfer,
                contextDir: contextDir,
                sender: sender,
                buildID: buildID
            )
        case "Info":
            try await handleFSSyncInfo(
                buildTransfer,
                contextDir: contextDir,
                sender: sender,
                buildID: buildID
            )
        case "Walk":
            try await handleFSSyncWalk(
                buildTransfer,
                contextDir: contextDir,
                sender: sender,
                buildID: buildID
            )
        default:
            logger.error("Unknown FSSync method: \(method)")
        }
    }

    private func handleFSSyncRead(
        _ packet: BuildTransfer,
        contextDir: URL,
        sender: AsyncStream<ClientStream>.Continuation,
        buildID: String
    ) async throws {
        let path = contextDir.appendingPathComponent(packet.source)
            .standardizedFileURL

        // Read file data
        let data: Data

        if FileManager.default.fileExists(atPath: path.path) {
            let offset = UInt64(packet.metadata["offset"] ?? "0") ?? 0
            let length = Int(packet.metadata["length"] ?? "0") ?? 0

            if path.hasDirectoryPath == true {
                data = Data()
            } else {
                let fileData = try Data(contentsOf: path)
                if offset == 0 && length == 0 {
                    data = fileData
                } else {
                    let start = Int(offset)
                    let end = length > 0 ? start + length : fileData.count
                    data = fileData.subdata(in: start..<min(end, fileData.count))
                }
            }
        } else {
            data = Data()
        }

        var response = ClientStream()
        response.buildID = buildID
        response.buildTransfer = BuildTransfer()
        response.buildTransfer.id = packet.id
        response.buildTransfer.source = packet.source
        response.buildTransfer.complete = true
        response.buildTransfer.direction = .outof
        response.buildTransfer.metadata = ["os": "linux", "stage": "fssync"]
        response.buildTransfer.data = data
        response.packetType = .buildTransfer(response.buildTransfer)
        sender.yield(response)
    }

    private func handleFSSyncInfo(
        _ packet: BuildTransfer,
        contextDir: URL,
        sender: AsyncStream<ClientStream>.Continuation,
        buildID: String
    ) async throws {
        let path = contextDir.appendingPathComponent(packet.source)
            .standardizedFileURL

        var response = ClientStream()
        response.buildID = buildID
        response.buildTransfer = BuildTransfer()
        response.buildTransfer.id = packet.id
        response.buildTransfer.source = packet.source
        response.buildTransfer.complete = true
        response.buildTransfer.direction = .outof
        response.buildTransfer.isDirectory = path.hasDirectoryPath
        response.buildTransfer.metadata = ["os": "linux", "stage": "fssync"]

        // Add file metadata if file exists
        if FileManager.default.fileExists(atPath: path.path),
            let attrs = try? FileManager.default.attributesOfItem(atPath: path.path)
        {
            if let size = attrs[.size] as? UInt64 {
                response.buildTransfer.metadata["size"] = String(size)
            }
            if let mode = attrs[.posixPermissions] as? NSNumber {
                response.buildTransfer.metadata["mode"] = String(mode.uint32Value)
            }
            if let modDate = attrs[.modificationDate] as? Date {
                let formatter = ISO8601DateFormatter()
                response.buildTransfer.metadata["modified_at"] = formatter.string(from: modDate)
            }
            response.buildTransfer.metadata["uid"] = "0"
            response.buildTransfer.metadata["gid"] = "0"
        }

        response.packetType = .buildTransfer(response.buildTransfer)
        sender.yield(response)
    }

    private func handleFSSyncWalk(
        _ packet: BuildTransfer,
        contextDir: URL,
        sender: AsyncStream<ClientStream>.Continuation,
        buildID: String
    ) async throws {
        let mode = packet.metadata["mode"] ?? "json"
        let followPaths = packet.metadata["followpaths"]?.split(separator: ",").map(String.init) ?? []

        logger.info("FSSync walk: contextDir=\(contextDir.path), mode=\(mode), followpaths=\(followPaths)")

        let matchedFiles = try matchPaths(contextDir: contextDir, followPaths: followPaths)

        logger.info(
            "FSSync walk matched \(matchedFiles.count) files: \(matchedFiles.prefix(5).map { $0.relativePath })"
        )

        if mode == "tar" {
            try await sendTarWalk(
                packet: packet,
                contextDir: contextDir,
                files: matchedFiles,
                sender: sender,
                buildID: buildID
            )
        } else {
            try sendJSONWalk(
                packet: packet,
                contextDir: contextDir,
                files: matchedFiles,
                sender: sender,
                buildID: buildID
            )
        }
    }

    private struct MatchedFile {
        let url: URL
        let relativePath: String
        let isDirectory: Bool
    }

    private func matchPaths(contextDir: URL, followPaths: [String]) throws -> [MatchedFile] {
        let fm = FileManager.default
        let root = contextDir.standardizedFileURL
        var results: [MatchedFile] = []

        for pattern in followPaths {
            let candidate = root.appendingPathComponent(pattern)
            if fm.fileExists(atPath: candidate.path) {
                let attrs = try fm.attributesOfItem(atPath: candidate.path)
                let isDir = (attrs[.type] as? FileAttributeType) == .typeDirectory
                results.append(MatchedFile(url: candidate, relativePath: pattern, isDirectory: isDir))
            }
        }

        results.sort { $0.relativePath < $1.relativePath }
        return results
    }

    private func sendJSONWalk(
        packet: BuildTransfer,
        contextDir: URL,
        files: [MatchedFile],
        sender: AsyncStream<ClientStream>.Continuation,
        buildID: String
    ) throws {
        let fm = FileManager.default
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let fileInfos = try files.map { match -> FSSyncFileInfo in
            let attrs = try fm.attributesOfItem(atPath: match.url.path)
            let size = (attrs[.size] as? UInt64) ?? 0
            let mode = (attrs[.posixPermissions] as? NSNumber)?.uint32Value ?? 0o644
            let modDate = (attrs[.modificationDate] as? Date) ?? Date()
            let target: String = {
                guard
                    (attrs[.type] as? FileAttributeType) == .typeSymbolicLink
                else { return "" }
                return (try? fm.destinationOfSymbolicLink(atPath: match.url.path))
                    ?? ""
            }()
            return FSSyncFileInfo(
                name: match.relativePath,
                modTime: formatter.string(from: modDate),
                mode: mode,
                size: size,
                isDir: match.isDirectory,
                uid: 0,
                gid: 0,
                target: target
            )
        }

        var response = ClientStream()
        response.buildID = buildID
        response.buildTransfer = BuildTransfer()
        response.buildTransfer.id = packet.id
        response.buildTransfer.source = packet.source
        response.buildTransfer.complete = true
        response.buildTransfer.direction = .outof
        response.buildTransfer.metadata = ["os": "linux", "stage": "fssync", "mode": "json"]
        response.buildTransfer.data = try JSONEncoder().encode(fileInfos)
        response.packetType = .buildTransfer(response.buildTransfer)
        sender.yield(response)
    }

    private func sendTarWalk(
        packet: BuildTransfer,
        contextDir: URL,
        files: [MatchedFile],
        sender: AsyncStream<ClientStream>.Continuation,
        buildID: String
    ) async throws {
        let tarURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".tar")
        defer { try? FileManager.default.removeItem(at: tarURL) }

        let hash = try writeTar(files: files, contextDir: contextDir, destination: tarURL)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        logger.info("FSSync tar walk created \(tarURL.lastPathComponent) hash=\(hashString)")

        // Send header packet with hash (no data yet)
        var header = BuildTransfer()
        header.id = packet.id
        header.source = tarURL.path
        header.complete = false
        header.direction = .outof
        header.metadata = ["os": "linux", "stage": "fssync", "mode": "tar", "hash": hashString]
        var headerResp = ClientStream()
        headerResp.buildID = buildID
        headerResp.buildTransfer = header
        headerResp.packetType = .buildTransfer(header)
        sender.yield(headerResp)

        // Stream tar file in chunks
        let chunkSize = 1 << 20  // 1 MiB
        guard let handle = try? FileHandle(forReadingFrom: tarURL) else {
            throw BuilderError.imageMissing
        }
        defer { try? handle.close() }

        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }

            var part = BuildTransfer()
            part.id = packet.id
            part.source = tarURL.path
            part.complete = false
            part.direction = .outof
            part.metadata = ["os": "linux", "stage": "fssync", "mode": "tar"]
            part.data = chunk

            var partResp = ClientStream()
            partResp.buildID = buildID
            partResp.buildTransfer = part
            partResp.packetType = .buildTransfer(part)
            sender.yield(partResp)
        }

        // Final packet (complete=true, no data)
        var done = BuildTransfer()
        done.id = packet.id
        done.source = tarURL.path
        done.complete = true
        done.direction = .outof
        done.metadata = ["os": "linux", "stage": "fssync", "mode": "tar"]

        var doneResp = ClientStream()
        doneResp.buildID = buildID
        doneResp.buildTransfer = done
        doneResp.packetType = .buildTransfer(done)
        sender.yield(doneResp)
    }

    private func writeTar(files: [MatchedFile], contextDir: URL, destination: URL) throws -> SHA256.Digest {
        let fm = FileManager.default

        try? fm.removeItem(at: destination)

        let config = ArchiveWriterConfiguration(format: .paxRestricted, filter: .none)
        let writer = try ArchiveWriter(configuration: config)

        try writer.open(file: destination)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        var hasher = SHA256()

        for match in files {
            let attrs = try fm.attributesOfItem(atPath: match.url.path)
            let entry = WriteEntry()
            entry.path = match.relativePath

            if let fileType = attrs[.type] as? FileAttributeType {
                switch fileType {
                case .typeDirectory:
                    entry.fileType = .directory
                case .typeSymbolicLink:
                    entry.fileType = .symbolicLink
                    entry.symlinkTarget = (try? fm.destinationOfSymbolicLink(atPath: match.url.path)) ?? ""
                case .typeRegular:
                    entry.fileType = .regular
                default:
                    continue
                }
            }

            if let perms = attrs[.posixPermissions] as? NSNumber {
                #if os(macOS)
                entry.permissions = perms.uint16Value
                #else
                entry.permissions = perms.uint32Value
                #endif
            }

            if let size = attrs[.size] as? UInt64 {
                entry.size = Int64(size)
            }

            entry.owner = 0
            entry.group = 0

            if let modDate = attrs[.modificationDate] as? Date {
                entry.modificationDate = modDate
            }

            hasher.update(data: try encoder.encode(entry))

            if entry.fileType == .regular {
                let data = try Data(contentsOf: match.url)
                hasher.update(data: data)
                try writer.writeEntry(entry: entry, data: data)
            } else {
                try writer.writeEntry(entry: entry, data: nil)
            }
        }

        try writer.finishEncoding()
        return hasher.finalize()
    }
}

private struct FSSyncFileInfo: Codable {
    let name: String
    let modTime: String
    let mode: UInt32
    let size: UInt64
    let isDir: Bool
    let uid: UInt32
    let gid: UInt32
    let target: String
}

extension WriteEntry: @retroactive Encodable {
    enum CodingKeys: String, CodingKey {
        case path
        case fileType
        case size
        case permissions
        case owner
        case group
        case symlinkTarget
        case hardlink
        case creationDate
        case modificationDate
        case contentAccessDate
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(fileType.rawValue, forKey: .fileType)
        try container.encodeIfPresent(permissions, forKey: .permissions)
        try container.encodeIfPresent(path, forKey: .path)
        try container.encodeIfPresent(size, forKey: .size)
        try container.encodeIfPresent(owner, forKey: .owner)
        try container.encodeIfPresent(group, forKey: .group)
        try container.encodeIfPresent(symlinkTarget, forKey: .symlinkTarget)
        try container.encodeIfPresent(hardlink, forKey: .hardlink)
        try container.encodeIfPresent(creationDate, forKey: .creationDate)
        try container.encodeIfPresent(modificationDate, forKey: .modificationDate)
        try container.encodeIfPresent(contentAccessDate, forKey: .contentAccessDate)
    }
}
