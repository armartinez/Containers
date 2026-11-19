//
//  SettingsView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import ContainersCore
import SwiftUI

struct SettingsView: View {
    @State private var selectedSection: SettingsPane? = .general
    @State private var sectionHistory: [SettingsPane] = [.general]
    @State private var sectionHistoryIndex = 0

    private var activeSection: SettingsPane {
        selectedSection ?? .general
    }

    private var canNavigateBack: Bool {
        sectionHistoryIndex > 0
    }

    private var canNavigateForward: Bool {
        sectionHistoryIndex < sectionHistory.count - 1
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selectedSection) { section in
                NavigationLink(value: section) {
                    SidebarRow(section: section)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(196)
            .fixedSidebarWidth(196)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            content
                .navigationTitle(activeSection.title)
                .toolbarTitleDisplayMode(.inlineLarge)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: navigateBack) {
                    Image(systemName: "chevron.left")
                }
                .help("Back")
                .disabled(!canNavigateBack)

                Button(action: navigateForward) {
                    Image(systemName: "chevron.right")
                }
                .help("Forward")
                .disabled(!canNavigateForward)
            }
        }
        .frame(minWidth: 760, minHeight: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: selectedSection) { oldValue, newValue in
            guard let newValue, newValue != oldValue else {
                return
            }

            recordSectionNavigation(to: newValue)
        }
    }

    private var content: some View {
        ScrollView {
            Group {
                switch activeSection {
                case .general:
                    GeneralSettingsView()
                case .network:
                    NetworkSettingsView()
                case .system:
                    SystemSettingsView()
                }
            }
            .frame(maxWidth: 520, alignment: .topLeading)
            .padding(24)
            // The toolbar's scroll edge spans the scroll view's content, so the content spans the whole pane.
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func navigateBack() {
        guard canNavigateBack else {
            return
        }

        sectionHistoryIndex -= 1
        selectedSection = sectionHistory[sectionHistoryIndex]
    }

    private func navigateForward() {
        guard canNavigateForward else {
            return
        }

        sectionHistoryIndex += 1
        selectedSection = sectionHistory[sectionHistoryIndex]
    }

    private func recordSectionNavigation(to section: SettingsPane) {
        guard sectionHistory.indices.contains(sectionHistoryIndex),
            sectionHistory[sectionHistoryIndex] != section
        else {
            return
        }

        if canNavigateForward {
            sectionHistory = Array(
                sectionHistory.prefix(sectionHistoryIndex + 1)
            )
        }

        sectionHistory.append(section)
        sectionHistoryIndex = sectionHistory.count - 1
    }
}

private struct SidebarRow: View {
    let section: SettingsPane

    var body: some View {
        Label {
            Text(section.title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: section.icon)
                .font(.system(size: 13, weight: .medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case network
    case system

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .network: "Network"
        case .system: "Container System"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape.fill"
        case .network: "network"
        case .system: "gauge.range.33to100.dotted.with.needle"
        }
    }
}

#Preview {
    SettingsView()
        .environment(NetworkManager.preview)
        .environment(ContainerSystem.preview)
}
