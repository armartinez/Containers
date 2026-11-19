//
//  Image+Icon.swift
//  Containers
//
//  Created by Axel Martinez on 2026/11/18.
//

import SwiftUI

extension Image {
    init(_ icon: Icon) {
        switch icon {
        case .system(let name): self.init(systemName: name)
        case .asset(let name): self.init(name)
        }
    }
}
