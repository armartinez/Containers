//
//  Release.swift
//  Containers
//
//  Created by Axel Martinez on 10/10/2026.
//

import Foundation

/// What the What's New sheet lists: the app's features on first launch, or
/// what changed in this release after an update.
enum AppInfo {
    struct Feature {
        let icon: String
        let title: String
        let description: String
    }

    /// The title and features the sheet shows.
    ///
    /// Worked out once, at launch: dismissing the sheet marks the version seen,
    /// which mustn't change what the closing sheet shows.
    static let release: (title: String, features: [Feature]) =
        UserDefaults.isFirstLaunch
        ? ("Welcome to", welcomeFeatures)
        : ("What's New in", updateFeatures)

    /// Whether an update to the version in the Info.plist shows `updateFeatures`.
    /// Set it for releases worth announcing; leave it off for small fixes.
    static let showsUpdateFeatures = false

    /// What changed in the version in the Info.plist. Replace it with each release.
    private static let updateFeatures: [Feature] = []

    private static let welcomeFeatures: [Feature] = [
        Feature(
            icon: "shippingbox",
            title: "Run Linux containers",
            description: "Create and run Linux containers as lightweight virtual machines on your Mac."
        ),
        Feature(
            icon: "cube.transparent",
            title: "OCI-compatible images support",
            description: "Pull and run images from container registries, build from a Dockerfile, or load from a local archive."
        ),
        Feature(
            icon: "cpu",
            title: "Optimized for Apple Silicon",
            description: "Written in Swift and designed to get the most out of Apple Silicon."
        ),
    ]
}
