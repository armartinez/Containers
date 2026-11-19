//
//  URL+Properties.swift
//  Containers
//
//  Created by Axel Martinez on 02/02/26.
//

import Foundation

extension URL {
    var parent: URL {
        self.appending(component: "..").standardized
    }

    var isFolder: Bool {
        (try? self.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }
}
