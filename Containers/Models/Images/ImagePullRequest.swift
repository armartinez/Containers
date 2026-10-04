//
//  ImagePullRequest.swift
//  Containers
//

import Foundation

/// What the Create Image sheet pulls.
struct ImagePullRequest {
    var imageName = ""
    var tag = "latest"
    var platform: PlatformSelection = .any

    var isComplete: Bool {
        !imageName.isEmpty
    }

    var reference: String {
        tag.isEmpty ? imageName : "\(imageName):\(tag)"
    }
}
