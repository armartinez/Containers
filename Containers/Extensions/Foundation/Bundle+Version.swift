//
//  Bundle+Version.swift
//  Containers
//
//  Created by Axel Martinez on 10/10/2026.
//

import Foundation

extension Bundle {
    /// The marketing version, such as `1.2`.
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
}
