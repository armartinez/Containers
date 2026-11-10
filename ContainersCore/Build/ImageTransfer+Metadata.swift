//
//  ImageTransfer+Metadata.swift
//  Containers
//

import ContainerizationOCI
import Foundation

extension ImageTransfer {
    init(id: String, digest: String, ref: String, platform: String, data: Data) throws {
        self.init()
        self.id = id
        self.tag = digest
        self.metadata = [
            "os": "linux",
            "stage": "resolver",
            "method": "/resolve",
            "ref": ref,
            "platform": platform,
        ]
        self.complete = true
        self.direction = .into
        self.data = data
    }

    func stage() -> String? {
        self.metadata["stage"]
    }

    func method() -> String? {
        self.metadata["method"]
    }

    func ref() -> String? {
        self.metadata["ref"]
    }

    func platform() throws -> Platform? {
        guard let platform = self.metadata["platform"] else {
            return nil
        }
        return try Platform(from: platform)
    }

    func mode() -> String? {
        self.metadata["mode"]
    }

    func size() -> Int? {
        guard let sizeString = self.metadata["size"] else {
            return nil
        }
        return Int(sizeString)
    }

    func len() -> Int? {
        guard let lengthString = self.metadata["length"] else {
            return nil
        }
        return Int(lengthString)
    }

    func offset() -> UInt64? {
        guard let offsetString = self.metadata["offset"] else {
            return nil
        }
        return UInt64(offsetString)
    }
}
