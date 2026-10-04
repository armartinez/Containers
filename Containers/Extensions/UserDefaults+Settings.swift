//
//  SettingsManager.swift
//  Containers
//
//  Created by Axel Martinez on 02/02/26.
//

import Foundation

@propertyWrapper
struct UserDefault<Value> {
    let key: String
    let defaultValue: Value
    var container: UserDefaults = UserDefaults.standard

    var wrappedValue: Value {
        get {
            container.object(forKey: key) as? Value ?? defaultValue
        }
        set {
            container.set(newValue, forKey: key)
        }
    }
}

extension UserDefaults {
    @UserDefault(key: "lastSeenVersion", defaultValue: "")
    static var lastSeenVersion: String

    @UserDefault(key: "lastSelectedTab", defaultValue: "images")
    static var lastSelectedTab: String

    @UserDefault(key: "startSystemTimeoutSeconds", defaultValue: 10)
    static var startSystemTimeoutSeconds: Int32

    @UserDefault(key: "stopContainerTimeoutSeconds", defaultValue: 5)
    static var stopContainerTimeoutSeconds: Int32

    @UserDefault(key: "shutdownSystemTimeoutSeconds", defaultValue: 20)
    static var shutdownSystemTimeoutSeconds: Int32

    private static let applicationDataRootKey = "applicationDataRoot"
    private static let applicationDataRootBookmarkKey = "applicationDataRootBookmark"
    private static let resolverDirectoryBookmarkKey = "resolverDirectoryBookmark"

    /// Named for the bundle, as Apple's `container` names its root.
    static var defaultAppRoot: URL {
        applicationSupport.appendingPathComponent(
            Foundation.Bundle.main.bundleIdentifier ?? "app.containers.Containers"
        )
    }

    /// Root directory for containers, images, volumes, kernels, and build data.
    static var applicationDataRoot: URL {
        get {
            if let bookmarkData = applicationDataRootBookmarkData {
                var isStale = false

                do {
                    let url = try URL(
                        resolvingBookmarkData: bookmarkData,
                        options: [.withSecurityScope],
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    )

                    if isStale,
                        let refreshedBookmark = try? url.bookmarkData(
                            options: [.withSecurityScope],
                            includingResourceValuesForKeys: nil,
                            relativeTo: nil
                        )
                    {
                        applicationDataRootBookmarkData = refreshedBookmark
                    }

                    return url
                } catch {
                    // Fall back to the stored URL or the default.
                }
            }

            return UserDefaults.standard.url(forKey: applicationDataRootKey) ?? defaultAppRoot
        }
        set {
            UserDefaults.standard.set(newValue, forKey: applicationDataRootKey)
        }
    }

    static var usesDefaultApplicationDataRoot: Bool {
        applicationDataRootBookmarkData == nil && applicationDataRoot.standardizedFileURL == defaultAppRoot.standardizedFileURL
    }

    static func setApplicationDataRoot(_ url: URL, bookmarkData: Data?) {
        applicationDataRoot = url
        applicationDataRootBookmarkData = bookmarkData
    }

    /// `nil` until the user grants access, or once the bookmark stops resolving.
    static var resolverDirectory: URL? {
        guard let bookmarkData = resolverDirectoryBookmarkData else {
            return nil
        }

        var isStale = false

        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale,
                let refreshedBookmark = try? url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            {
                resolverDirectoryBookmarkData = refreshedBookmark
            }

            return url
        } catch {
            // Forgotten, so the app asks again.
            resolverDirectoryBookmarkData = nil

            return nil
        }
    }

    static func setResolverDirectory(bookmarkData: Data) {
        resolverDirectoryBookmarkData = bookmarkData
    }

    static func resetApplicationDataRoot() {
        UserDefaults.standard.removeObject(forKey: applicationDataRootKey)
        applicationDataRootBookmarkData = nil
    }

    static var shouldShowWhatsNew: Bool {
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return lastSeenVersion != current
    }

    static func markCurrentVersionSeen() {
        lastSeenVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private static var resolverDirectoryBookmarkData: Data? {
        get {
            UserDefaults.standard.data(forKey: resolverDirectoryBookmarkKey)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(
                    newValue,
                    forKey: resolverDirectoryBookmarkKey
                )
            } else {
                UserDefaults.standard.removeObject(
                    forKey: resolverDirectoryBookmarkKey
                )
            }
        }
    }

    private static var applicationDataRootBookmarkData: Data? {
        get {
            UserDefaults.standard.data(forKey: applicationDataRootBookmarkKey)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(
                    newValue,
                    forKey: applicationDataRootBookmarkKey
                )
            } else {
                UserDefaults.standard.removeObject(
                    forKey: applicationDataRootBookmarkKey
                )
            }
        }
    }

    private static var applicationSupport: URL {
        guard
            let url = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else {
            fatalError("AppRoot unavailable")
        }

        return url
    }

    private static func escaped(_ path: String) -> String {
        path.replacingOccurrences(of: "/", with: "\\/")
    }
}
