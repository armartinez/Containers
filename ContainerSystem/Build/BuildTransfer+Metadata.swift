//
//  BuildTransfer+Metadata.swift
//  Containers
//

import Foundation

extension BuildTransfer {
    func stage() -> String? {
        let stage = self.metadata["stage"]
        return stage == "" ? nil : stage
    }

    func method() -> String? {
        let method = self.metadata["method"]
        return method == "" ? nil : method
    }

    func includePatterns() -> [String]? {
        guard let includePatternsString = self.metadata["include-patterns"] else {
            return nil
        }
        return includePatternsString == "" ? nil : includePatternsString.components(separatedBy: ",")
    }

    func followPaths() -> [String]? {
        guard let followPathString = self.metadata["followpaths"] else {
            return nil
        }
        return followPathString == "" ? nil : followPathString.components(separatedBy: ",")
    }

    func mode() -> String? {
        self.metadata["mode"]
    }

    func size() -> Int? {
        guard let sizeString = self.metadata["size"] else {
            return nil
        }
        return sizeString == "" ? nil : Int(sizeString)
    }

    func offset() -> UInt64? {
        guard let offsetString = self.metadata["offset"] else {
            return nil
        }
        return offsetString == "" ? nil : UInt64(offsetString)
    }

    func len() -> Int? {
        guard let lengthString = self.metadata["length"] else {
            return nil
        }
        return lengthString == "" ? nil : Int(lengthString)
    }
}
