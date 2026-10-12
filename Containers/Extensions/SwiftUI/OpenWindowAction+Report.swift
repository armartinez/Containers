//
//  OpenWindowAction+Report.swift
//  Containers
//
//  Created by Axel Martinez on 23/09/2026.
//

import SwiftUI

extension OpenWindowAction {
    func report(_ id: String) {
        self(id: ContainersApp.reportDetailWindowID, value: id)
    }
}
