//
//  NavigationTab.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import ContainerSystem

enum NavigationTab: String, Identifiable, Equatable {
    case containers
    case images
    case volumes
    case reports

    var displayTitle: String {
        switch self {
        case .containers:
            "Containers"
        case .images:
            "Images"
        case .volumes:
            "Volumes"
        case .reports:
            "Reports"
        }
    }

    var icon: String {
        switch self {
        case .containers:
            "shippingbox"
        case .images:
            "cube.transparent"
        case .volumes:
            "internaldrive"
        case .reports:
            "list.clipboard"
        }
    }

    /// Reports have no work of their own.
    var activityKind: ActivityCenter.Kind? {
        switch self {
        case .containers: .container
        case .images: .image
        case .volumes: .volume
        case .reports: nil
        }
    }

    /// An image is reported against as both an image and a build.
    var reportKinds: Set<Report.Kind>? {
        switch self {
        case .containers: [.container]
        case .images: [.image, .build]
        case .volumes: [.volume]
        case .reports: nil
        }
    }

    var id: String {
        self.rawValue
    }

    /// The toolbar buttons that act on the section's selected rows.
    var selectionItems: [SelectionToolbarItem] {
        switch self {
        case .containers: [.start, .stop, .details, .delete]
        case .images: [.run, .details, .delete]
        case .volumes: [.details, .delete]
        case .reports: [.details, .delete]
        }
    }

    static let allCases: [NavigationTab] = resources + records

    static let resources: [NavigationTab] = [.containers, .images, .volumes]

    static let records: [NavigationTab] = [.reports]
}
