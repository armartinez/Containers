//
//  View+PopoverTip.swift
//  Containers
//
//  Created by Axel Martinez on 01/08/2026.
//

import SwiftUI
import TipKit

extension View {
    @ViewBuilder
    func popoverTipIfPresent<T: Tip>(
        _ tip: T?,
        arrowEdge: Edge? = nil
    ) -> some View {
        if let tip {
            self.popoverTip(tip, arrowEdge: arrowEdge)
        } else {
            self
        }
    }

    @ViewBuilder
    func popoverTip<T: Tip>(
        _ tip: T,
        when condition: Bool,
        arrowEdge: Edge? = nil
    ) -> some View {
        if condition {
            self.popoverTip(tip, arrowEdge: arrowEdge)
        } else {
            self
        }
    }
}
