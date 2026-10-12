//
//  TerminalCommand.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/09.
//

import Foundation

/// Simple terminal command for sending responses to BuildKit
/// Matches the structure from ContainerBuild/TerminalCommand.swift
struct TerminalCommand: Codable {
    let commandType: String
    let code: String
    let rows: UInt16
    let cols: UInt16

    enum CodingKeys: String, CodingKey {
        case commandType = "command_type"
        case code
        case rows
        case cols
    }

    init() {
        self.commandType = "terminal"
        self.code = "ack"
        self.rows = 0
        self.cols = 0
    }

    func json() throws -> String {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        // CRITICAL: The command must be base64 encoded (without padding)
        return data.base64EncodedString().trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}
