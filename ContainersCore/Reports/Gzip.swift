//
//  Gzip.swift
//  Containers
//
//  Created by Axel Martinez on 20/09/2026.
//

import Compression
import Foundation

/// Compresses report bodies as standard gzip, so any tool can still open them.
enum Gzip {
    private static let header: [UInt8] = [
        0x1f, 0x8b,  // Magic number.
        0x08,  // Deflate.
        0x00,  // No flags.
        0x00, 0x00, 0x00, 0x00,  // No modification time; the manifest has it.
        0x00,  // No extra flags.
        0x03,  // Unix.
    ]

    static func compressed(_ text: String) -> Data? {
        let source = Data(text.utf8)

        guard !source.isEmpty else { return Data(header) + footer(for: source) }

        // Incompressible input can grow when deflated.
        let capacity = source.count + (source.count / 100) + 600
        var deflated = Data(count: capacity)

        let written = deflated.withUnsafeMutableBytes { destination in
            source.withUnsafeBytes { input in
                guard
                    let output = destination.bindMemory(to: UInt8.self)
                        .baseAddress,
                    let input = input.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }

                return compression_encode_buffer(
                    output,
                    capacity,
                    input,
                    source.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard written > 0 else { return nil }

        return Data(header) + deflated.prefix(written) + footer(for: source)
    }

    static func text(of data: Data) -> String? {
        guard data.count >= header.count + 8, data.starts(with: header.prefix(2)) else {
            return nil
        }

        // The last four bytes hold the uncompressed length.
        let size = Int(integer(at: data.endIndex - 4, of: data))

        guard size > 0 else { return "" }

        let deflated = data.dropFirst(header.count).dropLast(8)
        var inflated = Data(count: size)

        let written = inflated.withUnsafeMutableBytes { destination in
            deflated.withUnsafeBytes { input in
                guard
                    let output = destination.bindMemory(to: UInt8.self)
                        .baseAddress,
                    let input = input.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }

                return compression_decode_buffer(
                    output,
                    size,
                    input,
                    deflated.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard written > 0 else { return nil }

        return String(data: inflated.prefix(written), encoding: .utf8)
    }

    /// CRC-32 and length of the uncompressed data.
    private static func footer(for source: Data) -> Data {
        var footer = Data()

        for value in [crc32(of: source), UInt32(source.count & 0xffff_ffff)] {
            withUnsafeBytes(of: value.littleEndian) {
                footer.append(contentsOf: $0)
            }
        }

        return footer
    }

    private static func integer(at index: Data.Index, of data: Data) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { value, offset in
            value | UInt32(data[index + offset]) << (8 * UInt32(offset))
        }
    }

    private static let crcTable: [UInt32] = (0..<256).map { index in
        (0..<8).reduce(UInt32(index)) { value, _ in
            value & 1 == 1 ? 0xedb8_8320 ^ (value >> 1) : value >> 1
        }
    }

    private static func crc32(of data: Data) -> UInt32 {
        ~data.reduce(UInt32.max) { crc, byte in
            crcTable[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
        }
    }
}
