//
//  VolumeDetailView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/06/07.
//

import ContainerSystem
import SwiftUI

struct VolumeDetailView: View {
    @Environment(ReportManager.self) private var reportManager
    @Environment(\.openURL) private var openURL

    let volume: VolumeItem
    let toolbarController: DetailToolbarController

    /// Opens on what the volume is, which is what a window is opened to
    /// read; what it is called is there to be turned to.
    @SwiftUI.State private var selectedCategory: DetailCategory = .inspect

    enum DetailCategory: String, CaseIterable, Hashable {
        case inspect
        case info
    }

    static var toolbarTabs: [DetailToolbarController.Tab] {
        DetailCategory.allCases.map {
            .init(title: $0.rawValue.localizedCapitalized, icon: tabIcon($0))
        }
    }

    static func tabIcon(_ tab: DetailCategory) -> String {
        switch tab {
        case .info: "info.circle"
        case .inspect: "curlybraces"
        }
    }

    /// The same shape with nothing wired up, so the window can build its
    /// toolbar before it has a volume to build one from.
    static var placeholderToolbarItems: [DetailToolbarItem] {
        [.reportsPlaceholder]
    }

    private var toolbarItems: [DetailToolbarItem] {
        [
            .reports(
                about: volume.id,
                ofKind: [.volume],
                manager: reportManager,
                openURL: openURL
            )
        ]
    }

    var body: some View {
        DetailView(
            selectedTab: $selectedCategory,
            toolbarItems: toolbarItems,
            tabTitle: { category in
                category.rawValue.localizedCapitalized
            },
            tabIcon: { Self.tabIcon($0) },
            tabMaxHeight: { category in
                switch category {
                case .info: nil
                case .inspect: 500
                }
            },
            tabContentWidth: { category in
                switch category {
                case .info: DetailPlaceholder.width
                case .inspect: nil
                }
            },
            toolbarController: toolbarController,
            tabContent: { category in
                switch category {
                case .info:
                    VolumeInfo(volume: volume)
                case .inspect:
                    VolumeInspect(volume: volume)
                }
            }
        )
    }
}
