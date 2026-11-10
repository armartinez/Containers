//
//  DashboardView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import AppKit
import ContainersCore
import SwiftUI
import TipKit

struct DashboardView: View {
    @Environment(ContainerSystem.self) private var containerSystem
    @Environment(SystemActions.self) private var systemActions
    @Environment(ActivityCenter.self) private var activityCenter
    @Environment(ReportManager.self) private var reportManager
    @Environment(\.openWindow) private var openWindow

    @SwiftUI.State private var selectedTab: NavigationTab =
        NavigationTab(rawValue: UserDefaults.lastSelectedTab) ?? .images

    @SwiftUI.State private var errorAlert: ErrorAlert?

    @SwiftUI.State private var isFirstLaunch: Bool = UserDefaults.isFirstLaunch
    @SwiftUI.State private var didCancelSetup: Bool = false
    @SwiftUI.State private var showWhatsNew: Bool = UserDefaults.shouldShowWhatsNew
    @SwiftUI.State private var showSystemSetup: Bool = false
    /// After What's New, if it shows, since the two can't be on the window at once.
    @SwiftUI.State private var showSystemMode: Bool =
        UserDefaults.systemMode == nil && !UserDefaults.shouldShowWhatsNew
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

    private var isSystemRunning: Bool { containerSystem.isRunning }

    /// Beside the CLI, nothing can be added: the folder is its API server's to write.
    private var canAdd: Bool {
        !containerSystem.isReadOnly
    }

    private var containersBeingMade: Int {
        activityCenter.tasks(ofKind: .container).count
    }

    /// Only a first start, which has a folder to prepare, reports its steps.
    private var isMakingFolderReady: Bool {
        containerSystem.status == .starting && containerSystem.setupProgress != nil
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
                isAddEnabled: canAdd,
                showsClear: hasErrors,
                isFilterOn: runningContainersOnly,
                selectionItems: selectedTab.selectionItems,
                enabledSelectionItems: selectionActions.enabledItems,
                searchText: searchText,
                // Report filters as tokens; Return turns typed text into one.
                searchTokens: selectedTab == .reports ? reportFilters.map(\.token) : [],
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
        .task(reportManager.refresh)
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
                    // Until a mode is chosen, its sheet starts the system.
                    guard !self.isSystemRunning, !self.isFirstLaunch,
                        UserDefaults.systemMode != nil, UserDefaults.startsSystemOnOpen
                    else {
                        return
                    }

                    try? await self.containerSystem.start(
                        appRoot: UserDefaults.systemDataRoot
                    )
                }
                .errorAlert($errorAlert)
                .onChange(of: selectedTab) { _, newTab in
                    UserDefaults.lastSelectedTab = newTab.rawValue
                }
                .onOpenURL { url in
                    switch AppLink(url) {
                    case .containers:
                        // A typed search could hide the row the link leads to.
                        selectedTab = .containers
                        searchText = ""
                    case .reports where !reportManager.isAvailable:
                        break
                    case .reports(let name):
                        // Replaces the current filters and any typed search.
                        selectedTab = .reports
                        reportFilters = [.name(name)]
                        searchText = ""
                    case nil:
                        break
                    }
                }
                // Follows a new container to the tab its row appears in.
                .onChange(of: containersBeingMade) { before, now in
                    guard now > before else { return }

                    selectedTab = .containers
                }
                .onChange(of: systemActions.isAskingForKernel) { _, isAskingForKernel in
                    guard isAskingForKernel else { return }

                    didCancelSetup = false
                    showSystemSetup = true
                }
                .onChange(of: isMakingFolderReady) { _, _ in
                    guard isMakingFolderReady, !showWhatsNew,
                        !showSystemMode, !didCancelSetup
                    else {
                        return
                    }

                    showSystemSetup = true
                }
                .onChange(of: containerSystem.status) { _, status in
                    // Reports aren't kept beside the CLI.
                    if selectedTab == .reports, !reportManager.isAvailable {
                        selectedTab = .images
                    }

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
                        guard UserDefaults.systemMode != nil else {
                            showSystemMode = true
                            return
                        }

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
                    isPresented: $showSystemMode,
                    onDismiss: startChosenSystemMode,
                    content: {
                        SystemModeView(onChoose: chooseSystemMode)
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

    /// Whether a row on show is marked; a report with no row showing it doesn't count.
    private var hasErrors: Bool { !selectionActions.failures.isEmpty }

    /// Clears the marks on show by marking their reports read; the reports stay in Reports.
    private func clearErrors() {
        let failures = selectionActions.failures

        // A failure that left no report cannot be read, so it is let go of.
        for failure in failures where failure.reportID == nil {
            activityCenter.remove(failure.id)
        }

        let ids = failures.compactMap(\.reportID)

        guard !ids.isEmpty else { return }

        Task { await reportManager.markRead(ids) }
    }

    private func chooseSystemMode(_ mode: ContainerSystem.Mode) {
        UserDefaults.systemMode = mode
        containerSystem.mode = mode
        showSystemMode = false
    }

    /// A system of its own starts once chosen. The CLI's starts too, and Settings opens if the CLI's
    /// folder still has to be chosen; choosing it there starts the system.
    private func startChosenSystemMode() {
        switch UserDefaults.systemMode {
        case .default where isFirstLaunch:
            showSystemSetup = true
        case .default:
            // A folder that still needs the kernel brings up the setup sheet as it starts.
            Task { try? await containerSystem.start(appRoot: UserDefaults.systemDataRoot) }
        case .cliCompatibility:
            Task { try? await containerSystem.start(appRoot: UserDefaults.systemDataRoot) }

            // The sandbox lets the app into the CLI's folder only once it's chosen there.
            if UserDefaults.cliDataRoot == nil {
                openWindow(id: ContainersApp.settingsWindowID)
            }
        case nil:
            break
        }
    }

    private func handlePlusButton() {
        guard containerSystem.isRunning, canAdd else { return }

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
