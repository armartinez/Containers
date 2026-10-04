//
//  ImageLoadRequest.swift
//  Containers
//

import Foundation

/// What the Create Image sheet loads.
struct ImageLoadRequest {
    var tarFile: URL?
    var force = false

    var isComplete: Bool {
        tarFile != nil
    }
}
