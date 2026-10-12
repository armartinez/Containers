//
//  ImageLayer.swift
//  Containers
//
//  Created by Axel Martinez on 03/10/2026.
//

public struct ImageLayer {
    public let digest: String?
    public let size: Int64
    public let createdBy: String?
    public let comment: String?
    public let emptyLayer: Bool

    public init(
        digest: String?,
        size: Int64,
        createdBy: String?,
        comment: String?,
        emptyLayer: Bool
    ) {
        self.digest = digest
        self.size = size
        self.createdBy = createdBy
        self.comment = comment
        self.emptyLayer = emptyLayer
    }
}
