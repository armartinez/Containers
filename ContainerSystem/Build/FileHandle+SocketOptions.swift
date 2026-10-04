//
//  FileHandle+SocketOptions.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/09.
//

import Foundation

extension FileHandle {
    @discardableResult
    func setSendBufSize(_ bytes: Int) throws -> Int {
        try setSockOpt(level: SOL_SOCKET, name: SO_SNDBUF, value: bytes)
        return bytes
    }

    @discardableResult
    func setRecvBufSize(_ bytes: Int) throws -> Int {
        try setSockOpt(level: SOL_SOCKET, name: SO_RCVBUF, value: bytes)
        return bytes
    }

    private func setSockOpt(level: Int32, name: Int32, value: Int) throws {
        var socketValue = Int32(value)
        let result = withUnsafePointer(to: &socketValue) { pointer -> Int32 in
            pointer.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<Int32>.size) { rawPointer in
                setsockopt(self.fileDescriptor, level, name, rawPointer, socklen_t(MemoryLayout<Int32>.size))
            }
        }

        if result == -1 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM)
        }
    }
}
