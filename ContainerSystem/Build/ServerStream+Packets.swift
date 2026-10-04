//
//  ServerStream+Packets.swift
//  Containers
//

extension ServerStream {
    func getImageTransfer() -> ImageTransfer? {
        if case .imageTransfer(let transfer) = self.packetType {
            return transfer
        }
        return nil
    }

    func getBuildTransfer() -> BuildTransfer? {
        if case .buildTransfer(let transfer) = self.packetType {
            return transfer
        }
        return nil
    }

    func getIO() -> IO? {
        if case .io(let io) = self.packetType {
            return io
        }
        return nil
    }
}
