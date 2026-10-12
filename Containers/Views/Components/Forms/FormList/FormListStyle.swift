//
//  FormListStyle.swift
//  Containers
//
//  Created by Axel Martinez on 2026/08/09.
//

import SwiftUI

/// How an ``FormList`` draws itself. The rows, the selection and the
/// add and remove controls behave the same either way.
enum FormListStyle {
    /// Column headers over a full-height table, for wider layouts.
    case table

    /// A titled box sized to its rows, for settings panes.
    case grouped
}

private struct FormListStyleKey: EnvironmentKey {
    static let defaultValue: FormListStyle = .table
}

extension EnvironmentValues {
    var formListStyle: FormListStyle {
        get { self[FormListStyleKey.self] }
        set { self[FormListStyleKey.self] = newValue }
    }
}

extension View {
    func formListStyle(_ style: FormListStyle) -> some View {
        environment(\.formListStyle, style)
    }
}
