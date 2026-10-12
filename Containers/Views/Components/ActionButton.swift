//
//  ActionButton.swift
//  Containers
//
//  Created by Axel Martinez on 24/5/26.
//

import SwiftUI

struct ActionButton: View {
    let label: String
    let icon: String
    let help: String
    let action: () -> Void
    let role: ButtonRole? = nil

    init(
        label: String,
        icon: String,
        help: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.icon = icon
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(role: role) {
            action()
        } label: {
            Label(label, systemImage: icon)
        }
        .help(help)
    }
}

extension ActionButton: Equatable {
    static func == (lhs: ActionButton, rhs: ActionButton) -> Bool {
        lhs.help == rhs.help && lhs.label == rhs.label && lhs.icon == rhs.icon
            && lhs.role == rhs.role
    }
}
