//
//  URL+SameFolder.swift
//  Containers
//
//  Created by Axel Martinez on 2026/11/02.
//

import Foundation

extension URL {
    /// Whether both reach the same folder, through links or not.
    public func isSameFolder(as other: URL) -> Bool {
        resolvingSymlinksInPath().pathComponents == other.resolvingSymlinksInPath().pathComponents
    }
}
