//
//  BuildFailure.swift
//  Containers
//
//  Created by Axel Martinez on 16/09/2026.
//

import Foundation

public struct BuildFailure: LocalizedError {
    public let message: String
    public let transcript: String
    public var errorDescription: String? { message }

    public init(message: String, transcript: String) {
        self.message = message
        self.transcript = transcript
    }
}
