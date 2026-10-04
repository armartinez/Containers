//
//  DetailToolbarItem.swift
//  Containers
//
//  Created by Axel Martinez on 03/10/2026.
//

import ContainerSystem
import Foundation
import TipKit

/// An item in a detail window's toolbar.
struct DetailToolbarItem: Identifiable {
    let id: String
    let title: String
    let icon: String
    let help: String
    let isEnabled: Bool
    let isLeading: Bool
    /// An item that comes  and goes is hidden rather than removed,
    /// because changing a toolbar's items after the window opens
    /// fights AppKit as it lays them out.
    let isHidden: Bool
    let badgeCount: Int?
    let tip: AnyTip?
    let action: () -> Void

    init(
        id: String,
        title: String,
        icon: String,
        help: String? = nil,
        isEnabled: Bool = true,
        isHidden: Bool = false,
        isLeading: Bool = false,
        badgeCount: Int? = nil,
        tip: AnyTip? = nil,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.help = help ?? title
        self.isEnabled = isEnabled
        self.isHidden = isHidden
        self.isLeading = isLeading
        self.badgeCount = badgeCount
        self.tip = tip
        self.action = action
    }
}

extension DetailToolbarItem {
    /// The Reports item every detail window leads with: a badge with the
    /// unread reports about the window's subject, opening the Reports section
    /// filtered to it.
    ///
    /// `kinds` are what the subject can be reported as. An image is reported
    /// both as an image and as a build.
    static func reports(
        about name: String,
        ofKind kinds: Set<Report.Kind>,
        manager: ReportManager,
        openURL: OpenURLAction
    ) -> DetailToolbarItem {
        let reports = manager.reports(named: name, ofKind: kinds)
        let unread = reports.count { !$0.isRead }

        // Disabled rather than hidden when there's nothing to show: an item
        // that comes and goes changes the toolbar's items under AppKit.
        return DetailToolbarItem(
            id: "report",
            title: "Reports",
            icon: "list.bullet.clipboard",
            help: reports.isEmpty
                ? "Nothing reported" : "Show reports for \(name)",
            isEnabled: !reports.isEmpty,
            isLeading: true,
            badgeCount: unread
        ) {
            openURL(AppLink.reports(name: name).url)
        }
    }

    /// The Reports item before the window knows its subject, hidden and
    /// inert, so the toolbar can be built while the details load.
    static var reportsPlaceholder: DetailToolbarItem {
        DetailToolbarItem(
            id: "report",
            title: "Reports",
            icon: "list.bullet.clipboard",
            isEnabled: false,
            isHidden: true,
            isLeading: true
        ) {}
    }
}
