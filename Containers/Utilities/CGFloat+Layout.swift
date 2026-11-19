//
//  CGFloat+Layout.swift
//  Containers
//
//  Created by Axel Martinez on 10/08/2026.
//

import Foundation

extension CGFloat {
    /// Set on the label: a macOS button keeps its intrinsic width whatever its frame.
    static let sheetButtonLabelWidth: CGFloat = 64

    static let fieldControlWidth: CGFloat = 260

    /// Between a sheet's progress or failure mark and the text below it.
    nonisolated static let sheetMarkSpacing: CGFloat = 12

    /// Shared by every strip across a window, so scope bars and sheet tabs match.
    static let barHeight: CGFloat = 30
}
