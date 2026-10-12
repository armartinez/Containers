//
//  View+DefaultAction.swift
//  Containers
//
//  Created by Axel Martinez on 09/08/2026.
//

import SwiftUI

extension View {
    /// Disabled, it drops to a plain button, as AppKit's default button does.
    @ViewBuilder
    func defaultAction(enabled: Bool) -> some View {
        if enabled {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered).disabled(true)
        }
    }
}
