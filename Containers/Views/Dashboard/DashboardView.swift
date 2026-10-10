//
//  DashboardView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import AppKit
import ContainerSystem
import SwiftUI
import TipKit

struct DashboardView: View {
    @Environment(SystemManager.self) private var system
    @Environment(ActivityCenter.self) private var activityCenter
    @Environment(ReportManager.self) private var reportManager

    @SwiftUI.State private var selectedTab: NavigationTab =
        NavigationTab(rawValue: UserDefaults.lastSelectedTab) ?? .images

    @SwiftUI.State private var errorAlert: ErrorAlert?

    @SwiftUI.State private var isFirstLaunch: Bool = UserDefaults.isFirstLaunch
    @SwiftUI.State private var didCancelSetup: Bool = false
    @SwiftUI.State private var showWhatsNew: Bool = UserDefaults.shouldShowWhatsNew
    @SwiftUI.State private var showSystemSetup: Bool = false
    @SwiftUI.State private var creationSheet: CreationSheet?

    private enum CreationSheet: Identifiable {
        case container
        case image
        case volume

        var id: Self { self }
    }

    /// Bumped to make the tables reload, as when the Create Image sheet closes.
    @SwiftUI.State private var refreshTrigger: Int = 0
    @SwiftUI.State private var searchText: String = ""
    @SwiftUI.State private var runningContainersOnly: Bool = false
    @SwiftUI.State private var containerSelection: Set<ContainerItem.ID> = []
    @SwiftUI.State private var imageSelection: Set<ImageItem.ID> = []
    @SwiftUI.State private var volumeSelection: Set<VolumeItem.ID> = []
    @SwiftUI.State private var reportSelection: Set<Report.ID> = []
    @SwiftUI.State private var reportFilters: [ReportFilter] = []

    @SwiftUI.State private var selectionActions = SelectionActions()
    @SwiftUI.State private var selectionCommand: SelectionCommand?

    @SwiftUI.State private var toolbarController = DashboardToolbarController()
    @SwiftUI.State private var showAddFirstImageTip: Bool = false
    @SwiftUI.State private var showRunContainerTip: Bool = false

    private let addFirstImageTip = AddFirstImageTip()
    private let runContainerTip = RunContainerTip()

    private var isSystemRunning: Bool { system.status == .running }

    private var containersBeingMade: Int {
        activityCenter.activities(ofKind: .container).count
    }

    /// Only a first start, which has a folder to prepare, reports its steps.
    private var isMakingFolderReady: Bool {
        system.status == .starting && system.setupProgress != nil
    }

    @ViewBuilder private var tabContent: some View {
        switch selectedTab {
        case .containers:
            ContainersView(
                searchText: $searchText,
                runningContainersOnly: $runningContainersOnly,
                selection: $containerSelection,
                actions: $selectionActions,
                command: $selectionCommand,
                refreshTrigger: refreshTrigger
            )
            // Not padding: the table must run under the toolbar, or AppKit
            // draws a line under it.
            .safeAreaPadding(.top)
        case .images:
            ImagesView(
                searchText: $searchText,
                selection: $imageSelection,
                actions: $selectionActions,
                command: $selectionCommand,
                refreshTrigger: refreshTrigger
            )
            .safeAreaPadding(.top)
        case .volumes:
            VolumesView(
                searchText: $searchText,
                selection: $volumeSelection,
                actions: $selectionActions,
                command: $selectionCommand,
                refreshTrigger: refreshTrigger
            )
            .safeAreaPadding(.top)
        case .reports:
            ReportsView(
                searchText: $searchText,
                selection: $reportSelection,
                actions: $selectionActions,
                command: $selectionCommand,
                filters: $reportFilters,
                refreshTrigger: refreshTrigger
            )
        }
    }

    var body: some View {
        NavigationSplitView {
            DashboardSidebar(selection: $selectedTab)
                .disabled(!isSystemRunning)
        } detail: {
            detail
        }
        .navigationTitle(selectedTab.displayTitle)
        .frame(minWidth: 560, minHeight: 320)
        .background(
            DashboardToolbarBinder(
                controller: toolbarController,
                title: selectedTab.displayTitle,
                isEnabled: isSystemRunning,
                showsFilter: selectedTab == .containers,
                showsAdd: selectedTab != .reports,
                showsClear: hasErrors,
                isFilterOn: runningContainersOnly,
                selectionItems: selectedTab.selectionItems,
                enabledSelectionItems: selectionActions.enabledItems,
                searchText: searchText,
                // Report filters as tokens; Return turns typed text into one.
                searchTokens: selectedTab == .reports
                    ? reportFilters.map(\.token) : [],
                onDeleteSearchTokens: { reportFilters.remove(atOffsets: $0) },
                onChooseSearchTokenOption: { index, title in
                    guard reportFilters.indices.contains(index) else { return }

                    reportFilters[index] = reportFilters[index].choosing(title)
                },
                onSubmitSearch: selectedTab == .reports
                    ? { text in
                        reportFilters.append(ReportFilter(field: .any, value: text))
                        searchText = ""
                    } : nil,
                onToggleFilter: { runningContainersOnly = $0 },
                onAdd: {
                    addFirstImageTip.invalidate(reason: .actionPerformed)
                    handlePlusButton()
                },
                onClear: clearErrors,
                onSelectionItem: { selectionCommand = $0.command },
                onSearch: { searchText = $0 },
                addTip: showAddFirstImageTip
                    ? AnyView(TipView(addFirstImageTip)) : nil,
                runTip: showRunContainerTip && selectedTab == .images
                    && selectionActions.canStart
                    ? AnyView(TipView(runContainerTip)) : nil,
                // Only while there's a table to narrow.
                accessory: selectedTab == .reports && isSystemRunning
                    ? AnyView(SearchBar(filters: $reportFilters)) : nil
            )
        )
        // A window opened onto a running system never sees it start.
        .task {
            await reportManager.refresh()
        }
        .task {
            // `.popoverTip` can't attach to an AppKit toolbar item.
            for await shouldDisplay in addFirstImageTip.shouldDisplayUpdates {
                showAddFirstImageTip = shouldDisplay
            }
        }
        .task {
            for await shouldDisplay in runContainerTip.shouldDisplayUpdates {
                showRunContainerTip = shouldDisplay
            }
        }
    }

    private var detail: some View {
        VStack(spacing: 0) {
            tabContent
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .disabled(!isSystemRunning)
                .overlay {
                    if !isSystemRunning {
                        SystemStatusView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(nsColor: .windowBackgroundColor))
                    }
                }
                .task {
                    guard !self.isSystemRunning, !self.isFirstLaunch else {
                        return
                    }

                    try? await self.system.start(
                        appRoot: UserDefaults.applicationDataRoot
                    )
                }
                .errorAlert($errorAlert)
                .onChange(of: selectedTab) { _, newTab in
                    UserDefaults.lastSelectedTab = newTab.rawValue
                }
                // Replaces the current filters and any typed search.
                .onOpenURL { url in
                    guard case .reports(let name) = AppLink(url) else { return }

                    selectedTab = .reports
                    reportFilters = [.name(name)]
                    searchText = ""
                }
                // Follows a new container to the tab its row appears in.
                .onChange(of: containersBeingMade) { before, now in
                    guard now > before else { return }

                    selectedTab = .containers
                }
                .onChange(of: isMakingFolderReady) { _, _ in
                    guard isMakingFolderReady, !showWhatsNew,
                        !didCancelSetup
                    else {
                        return
                    }

                    showSystemSetup = true
                }
                .onChange(of: system.status) { _, status in
                    // A run that ended clears the cancel, so the next can
                    // show the sheet.
                    guard status != .starting else { return }

                    didCancelSetup = false

                    if status == .running {
                        Task { await reportManager.refresh() }
                    }
                }
                .sheet(
                    isPresented: $showWhatsNew,
                    onDismiss: {
                        showSystemSetup = isFirstLaunch || isMakingFolderReady
                    },
                    content: {
                        WhatsNewView {
                            UserDefaults.markCurrentVersionSeen()
                            showWhatsNew = false
                        }
                    }
                )
                .sheet(
                    isPresented: $showSystemSetup,
                    onDismiss: {
                        guard isFirstLaunch, isSystemRunning else { return }

                        AddFirstImageTip.shouldShow = true
                    },
                    content: {
                        SystemSetupView(onCancel: { didCancelSetup = true })
                    }
                )
                .sheet(
                    item: $creationSheet,
                    onDismiss: { refreshTrigger += 1 }
                ) { sheet in
                    switch sheet {
                    case .container: CreateContainerView(imageReference: "")
                    case .image: CreateImageView()
                    case .volume: CreateVolumeView()
                    }
                }

            DashboardStatusBar(errorAlert: $errorAlert)
        }
    }

    /// The unread reports behind the section's marks.
    private var unreadReports: [String] {
        guard let kinds = selectedTab.reportKinds else { return [] }

        return reportManager.reports
            .filter { kinds.contains($0.kind) && !$0.isRead }
            .map(\.id)
    }

    /// Whether the section on show is marked anywhere.
    private var hasErrors: Bool {
        guard let kind = selectedTab.activityKind else { return false }

        return !unreadReports.isEmpty
            || activityCenter.hasUnreportedFailures(ofKind: kind)
    }

    /// Clears the section's marks by marking their reports read; the reports
    /// stay in Reports.
    private func clearErrors() {
        guard let kind = selectedTab.activityKind else { return }

        // A failure that left no report cannot be read, so it is let go of.
        activityCenter.forgetUnreportedFailures(ofKind: kind)

        let ids = unreadReports

        guard !ids.isEmpty else { return }

        Task { await reportManager.markRead(ids) }
    }

    private func handlePlusButton() {
        guard system.status == .running else { return }

        switch selectedTab {
        case .containers:
            creationSheet = .container
        case .volumes:
            creationSheet = .volume
        case .images:
            creationSheet = .image
        case .reports:
            break
        }
    }

}
