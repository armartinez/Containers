//
//  NSSavePanel+Sheet.swift
//  Containers
//
//  Created by Axel Martinez on 30/10/2026.
//

import AppKit

extension NSSavePanel {
    /// Attaches the panel to the key window, which is the sheet when one is open, or runs it on its own without one.
    /// - Returns: The chosen URL, or `nil` if the user cancelled.
    func presentAsSheet() async -> URL? {
        let response: NSApplication.ModalResponse

        if let window = NSApp.keyWindow {
            response = await beginSheetModal(for: window)
        } else {
            response = runModal()
        }

        guard response == .OK else { return nil }

        return url
    }
}
