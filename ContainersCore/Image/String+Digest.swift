//
//  String+Digest.swift
//  Containers
//
//  Created by Axel Martinez on 2026/09/19.
//

import Foundation

extension String {
    /// The digest without its algorithm, whichever one it is.
    public var digestHex: String {
        guard let colonIndex = firstIndex(of: ":") else {
            return self
        }

        return String(self[index(after: colonIndex)...])
    }

    public var trimmedDigest: String {
        String(digestHex.prefix(12))
    }
}
