//
//  DashboardSidebar.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import ContainerSystem
import SwiftUI

struct DashboardSidebar: View {
    @Environment(ReportManager.self) private var reportManager
    @Environment(\.sidebarRowSize) private var sidebarRowSize

    @Binding var selection: NavigationTab

    var body: some View {
        List(selection: listSelection) {
            // Resources need no header; reports get a section of their own.
            ForEach(NavigationTab.resources, content: row)

            Section("Activity") {
                ForEach(NavigationTab.records, content: row)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        // The toolbar is AppKit's, which carries its own toggle.
        .toolbar(removing: .sidebarToggle)
    }

    private func row(for tab: NavigationTab) -> some View {
        Label {
            Text(tab.displayTitle)
        } icon: {
            // Console's icon size; `imageScale` is ignored in a sidebar.
            Image(systemName: tab.icon)
                .font(.system(size: iconSize))
        }
        // Unread reports, counted as Mail counts unread mail.
        .badge(tab == .reports ? reportManager.unreadCount : 0)
        .tag(tab)
    }

    private var iconSize: CGFloat {
        switch sidebarRowSize {
        case .small: 14
        case .large: 21
        default: 17
        }
    }

    /// A sidebar always has a section chosen.
    private var listSelection: Binding<NavigationTab?> {
        Binding(
            get: { selection },
            set: { tab in
                guard let tab else { return }
                selection = tab
            }
        )
    }
}
