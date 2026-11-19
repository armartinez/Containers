//
//  Icon.swift
//  Containers
//
//  Created by Axel Martinez on 2026/11/18.
//

/// A system symbol, or one of the app's own in the asset catalog.
enum Icon {
    case system(String)
    case asset(String)

    static let container = Icon.asset("container")
    static let image = Icon.asset("image")
    static let volume = Icon.asset("volume")
}
