//
//  ContainerSystem+Preview.swift
//  Containers
//
//  Stand-ins for SwiftUI previews, so they never start or read the real container system.
//
//  Created by Axel Martinez on 2026/11/10.
//

#if DEBUG
extension ContainerSystem {
    /// A container system that is never started, with a container CLI that is installed and stopped.
    public static let preview = ContainerSystem()
}

extension ContainerManager {
    public static let preview = ContainerManager(testSystem: .preview)
}

extension NetworkManager {
    public static let preview = NetworkManager(testSystem: .preview)
}

extension ReportManager {
    public static let preview = ReportManager(testSystem: .preview)
}
#endif
