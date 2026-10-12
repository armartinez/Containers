//
//  Report+Appearance.swift
//  Containers
//
//  Created by Axel Martinez on 22/09/2026.
//

import ContainerSystem
import SwiftUI

extension Report {
    /// Filled until read, hollow after.
    var symbol: String {
        let name =
            switch level {
            case .warning: "exclamationmark.triangle"
            case .error: "xmark.octagon"
            }

        return isRead ? name : "\(name).fill"
    }

    var color: Color {
        switch level {
        case .warning: .yellow
        case .error: .red
        }
    }
}
