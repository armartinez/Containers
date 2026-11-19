//
//  View+Foreground.swift
//  Containers
//
//  Created by Axel Martinez on 12/10/2026.
//

import SwiftUI

extension View {
    /// Shows a cell's content as secondary while nothing can be done with its row, or while `isDimmed` holds.
    func rowForeground(for row: some TaskRow, isDimmed: Bool = false) -> some View {
        foregroundStyle(row.isDisabled || isDimmed ? .secondary : .primary)
    }
}
