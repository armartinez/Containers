//
//  ImageBuildRequest.swift
//  Containers
//

import ContainerSystem
import ContainerizationOCI
import Foundation

/// What the Create Image sheet builds.
struct ImageBuildRequest {
    var contextDirectory: URL?
    var dockerFile: URL?
    var tag = ""
    var platform: PlatformSelection = .platform(.current)
    var arguments: [KeyValue] = []
    var targetStage = ""

    var isComplete: Bool {
        contextDirectory != nil && dockerFile != nil
    }

    /// The tag, or a generated one when it's empty, so the row has a title.
    func resolvedTag() -> String {
        tag.isEmpty ? UUID().uuidString.lowercased() : tag
    }

    var targetPlatform: Platform {
        platform.platform ?? .current
    }

    var namedArguments: [KeyValue] {
        arguments.filter {
            !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
