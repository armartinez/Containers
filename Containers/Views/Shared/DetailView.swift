//
//  DetailView.swift
//  Containers
//
//  Created by Axel Martinez on 23/5/26.
//

import AppKit
import SwiftUI
import TipKit

/// The size each detail window opens at, before its content has loaded.
///
/// Measured from the size each window settles at on its first tab, so it
/// doesn't resize right after opening. One shared size would be wrong for all:
/// a log fills its tab, while a volume's inspect is a dozen lines.
enum DetailPlaceholder {
    static let container = CGSize(width: 900, height: 450)
    static let image = CGSize(width: 900, height: 430)
    static let volume = CGSize(width: 900, height: 225)
    static let report = CGSize(width: 900, height: 560)
    static let width: CGFloat = 550
    static let minimumHeight: CGFloat = 140

    /// Places the window just below the toolbar of the window it was opened
    /// from, centred across it.
    /// `parent` is in AppKit's bottom-up coordinates; `display` is top-down,
    /// from the top of the screen's usable area.
    static func underParentToolbar(
        on display: CGRect,
        size: CGSize
    ) -> WindowPlacement {
        guard
            let parent = NSApp.keyWindow,
            let screen = parent.screen
        else {
            return WindowPlacement(.center, size: size)
        }

        let visible = screen.visibleFrame
        let top = parent.frame.maxY - chromeHeight(of: parent)

        return WindowPlacement(
            CGPoint(
                x: display.minX + (parent.frame.midX - visible.minX)
                    - size.width / 2,
                y: display.minY + (visible.maxY - top)
            ),
            size: size
        )
    }

    /// The height of the title bar and toolbar together.
    private static func chromeHeight(of window: NSWindow) -> CGFloat {
        let titlebar = window.standardWindowButton(.closeButton)?.superview

        return titlebar?.frame.height
            ?? window.frame.height - window.contentLayoutRect.height
    }
}

/// Sizes the window to each tab's content: hide, load, resize, show.
///
/// Requires `.windowResizability(.contentMinSize)` on the enclosing scene:
/// `.contentSize` clamps the resize animation's intermediate frames.
struct DetailView<
    Tab: Hashable & CaseIterable,
    Content: View
>: View where Tab.AllCases: RandomAccessCollection {
    private var defaultMinWidth: CGFloat { DetailPlaceholder.width }
    private var maximumWidth: CGFloat { 900 }
    private var minimumHeight: CGFloat { DetailPlaceholder.minimumHeight }
    private var maximumHeight: CGFloat {
        guard let visible = resizer.visibleScreenHeight else { return 720 }
        return max(minimumHeight, visible - 160)
    }

    private let fadeDuration: TimeInterval = 0.1
    private let resizeDuration: TimeInterval = 0.18
    private let readyTimeout: Duration = .seconds(2)
    private let toolbarTimeout: Duration = .milliseconds(500)

    let showTabs: Bool
    let toolbarItems: [DetailToolbarItem]

    @Binding var selectedTab: Tab

    let tabTitle: (Tab) -> String
    let tabIcon: (Tab) -> String
    let tabWidth: (Tab) -> CGFloat?
    let tabMaxHeight: (Tab) -> CGFloat?
    let tabContentWidth: (Tab) -> CGFloat?
    let tabContent: (Tab) -> Content

    private let injectedToolbarController: DetailToolbarController?

    @State private var displayedTab: Tab
    @State private var contentOpacity: Double = 0
    @State private var measuredHeight: CGFloat = 0
    @State private var measuredWidth: CGFloat = 0
    @State private var naturalWidth: CGFloat = 0
    @State private var heightOverflows = false
    @State private var widthOverflows = false
    @State private var pendingTab: Tab?
    @State private var isTransitioning = false
    @State private var needsRefit = false
    @State private var hasMeasured = false
    @State private var hasAwaitedToolbar = false
    @State private var resizer = WindowResizer()
    /// Used when the window supplied none. Attaching it early keeps the
    /// chrome from changing under the first fit.
    @State private var ownToolbarController = DetailToolbarController()

    init(
        selectedTab: Binding<Tab>,
        showTabs: Bool = true,
        toolbarItems: [DetailToolbarItem] = [],
        tabTitle: @escaping (Tab) -> String,
        tabIcon: @escaping (Tab) -> String,
        tabWidth: @escaping (Tab) -> CGFloat? = { _ in nil },
        tabMaxHeight: @escaping (Tab) -> CGFloat? = { _ in nil },
        tabContentWidth: @escaping (Tab) -> CGFloat? = { _ in nil },
        toolbarController: DetailToolbarController? = nil,
        @ViewBuilder tabContent: @escaping (Tab) -> Content
    ) {
        self.injectedToolbarController = toolbarController
        self._selectedTab = selectedTab
        self._displayedTab = State(initialValue: selectedTab.wrappedValue)
        self.showTabs = showTabs
        self.toolbarItems = toolbarItems
        self.tabTitle = tabTitle
        self.tabIcon = tabIcon
        self.tabWidth = tabWidth
        self.tabMaxHeight = tabMaxHeight
        self.tabContentWidth = tabContentWidth
        self.tabContent = tabContent
    }

    private var effectiveMinWidth: CGFloat {
        tabWidth(displayedTab) ?? defaultMinWidth
    }

    private var heightCap: CGFloat {
        min(tabMaxHeight(displayedTab) ?? maximumHeight, maximumHeight)
    }

    /// How wide the user can drag the window, as opposed to how wide it opens.
    /// Content that's cut off can be dragged into view, so the limit is the
    /// content's own width rather than the opening width. Height works the
    /// same way.
    private var dragMaximumWidth: CGFloat {
        guard widthOverflows else { return maximumWidth }

        // Stops once all the content shows, or at the screen's edge.
        return min(naturalWidth, resizer.visibleScreenWidth ?? naturalWidth)
    }

    private var windowConstraints: WindowConstraints {
        WindowConstraints(
            heightIsFixed: !heightOverflows,
            widthIsFixed: !widthOverflows,
            minWidth: effectiveMinWidth,
            maxWidth: dragMaximumWidth
        )
    }

    private var toolbarController: DetailToolbarController {
        injectedToolbarController ?? ownToolbarController
    }

    private var toolbarTabs: [DetailToolbarController.Tab] {
        Array(Tab.allCases).map {
            .init(title: tabTitle($0), icon: tabIcon($0))
        }
    }

    private var sizedContent: some View {
        DetailLayout(
            minWidth: effectiveMinWidth,
            maxWidth: maximumWidth,
            onIdealSize: fitTo
        ) {
            tabContent(displayedTab)
                .frame(maxWidth: tabContentWidth(displayedTab) ?? .infinity)
                .frame(maxWidth: .infinity)
        }
    }

    private func fitTo(idealSize: CGSize) {
        // Zero from a tab with a bound is unbounded content, not empty.
        let unbounded = idealSize.height <= 0 && tabMaxHeight(displayedTab) != nil
        let ideal = unbounded ? heightCap : idealSize.height

        guard ideal > 0 else { return }

        let height = min(max(ideal, minimumHeight), heightCap)
        let width = min(max(idealSize.width, effectiveMinWidth), maximumWidth)

        // Only content the window cannot show all of is worth dragging for.
        // Unbounded content scrolls both ways, so it always has more to give.
        let overflowsHeight = unbounded || ideal > height + 0.5
        let overflowsWidth = idealSize.width > width + 0.5

        // `awaitMeasurement` waits on the first report after a swap, so it
        // gets through even when it matches the outgoing height.
        guard
            !hasMeasured
                || abs(measuredHeight - height) > 0.5
                || abs(measuredWidth - width) > 0.5
                || abs(naturalWidth - idealSize.width) > 0.5
                || overflowsHeight != heightOverflows
                || overflowsWidth != widthOverflows
        else { return }

        // Runs from layout, so the writes are deferred.
        Task { @MainActor in
            measuredHeight = height
            measuredWidth = width
            naturalWidth = idealSize.width
            heightOverflows = overflowsHeight
            widthOverflows = overflowsWidth
            hasMeasured = true
        }
    }

    var body: some View {
        // The window sizes itself from this spacer, not the content: an
        // overlay doesn't report its height, and any other width makes
        // SwiftUI grow the window from its left edge, off centre.
        Color.clear
            // Flexible both ways. `maximumWidth` only limits how wide the
            // window opens; capping the layout too kept content at 900 points
            // inside a window dragged wider, leaving it hidden.
            .frame(minWidth: defaultMinWidth, maxWidth: .infinity)
            .frame(minHeight: minimumHeight, maxHeight: .infinity)
            .overlay(alignment: .top) {
                sizedContent
                    .opacity(contentOpacity)
            }
            .background(.windowBackground)
            .clipped()
            .background(WindowBinder(resizer: resizer))
            .background(
                DetailToolbarBinder(
                    controller: toolbarController,
                    tabs: showTabs ? toolbarTabs : [],
                    selectedIndex: Array(Tab.allCases)
                        .firstIndex(of: displayedTab) ?? 0,
                    items: toolbarItems,
                    onSelectTab: { index in
                        let all = Array(Tab.allCases)
                        guard all.indices.contains(index) else { return }
                        selectedTab = all[index]
                    }
                )
            )
            .onChange(of: windowConstraints, initial: true) { _, constraints in
                resizer.setConstraints(constraints)
            }
            .onChange(of: measuredHeight) { _, height in
                guard height > 0 else { return }

                guard !isTransitioning else {
                    needsRefit = true
                    return
                }

                Task {
                    await resizer.fit(
                        size: CGSize(width: measuredWidth, height: height),
                        duration: resizeDuration
                    )
                }
            }
            .onChange(of: selectedTab) { _, tab in
                requestTransition(to: tab)
            }
            // The first tab fades in like any other: after its measurement, or
            // once `awaitMeasurement` gives up waiting for one.
            .onAppear {
                requestTransition(to: displayedTab)
            }
    }

    private func requestTransition(to tab: Tab) {
        pendingTab = tab

        guard !isTransitioning else { return }

        Task { await runTransitions() }
    }

    /// Drains `pendingTab`, so switching again queues rather than restarts.
    private func runTransitions() async {
        isTransitioning = true
        defer { isTransitioning = false }

        // Sizing before the toolbar lands measures the title bar alone, and
        // the toolbar then drags it straight — two moves for one appearance.
        if !hasAwaitedToolbar {
            hasAwaitedToolbar = true
            await toolbarController.whenSettled(timeout: toolbarTimeout)
        }

        while pendingTab != nil || needsRefit {
            guard pendingTab != nil else {
                needsRefit = false
                await resizer.fit(
                    size: CGSize(
                        width: measuredWidth,
                        height: measuredHeight
                    ),
                    duration: resizeDuration
                )
                continue
            }

            await fade(to: 0)

            guard let tab = pendingTab else { break }

            pendingTab = nil

            if tab != displayedTab {
                hasMeasured = false
                displayedTab = tab
            }

            await awaitMeasurement()

            guard pendingTab == nil else { continue }

            needsRefit = false

            // Content that never reported a size shows at the size it has.
            if hasMeasured {
                await resizer.fit(
                    size: CGSize(width: measuredWidth, height: measuredHeight),
                    duration: resizeDuration
                )
            }
            guard pendingTab == nil else { continue }

            await fade(to: 1)
        }

        await fade(to: 1)
    }

    /// For a tab that fetches its own data, the whole of the load.
    private func awaitMeasurement() async {
        let deadline = ContinuousClock.now.advanced(by: readyTimeout)

        while !hasMeasured, ContinuousClock.now < deadline {
            guard pendingTab == nil else { return }

            await Task.yield()

            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    private func fade(to opacity: Double) async {
        guard contentOpacity != opacity else { return }

        await withCheckedContinuation { continuation in
            withAnimation(.easeInOut(duration: fadeDuration)) {
                contentOpacity = opacity
            } completion: {
                continuation.resume()
            }
        }
    }

    private struct DetailLayout: Layout {
        let minWidth: CGFloat
        let maxWidth: CGFloat
        let onIdealSize: @MainActor @Sendable (CGSize) -> Void

        func sizeThatFits(
            proposal: ProposedViewSize,
            subviews: Subviews,
            cache: inout ()
        ) -> CGSize {
            guard let subview = subviews.first else { return .zero }

            let declared = subview.contentIdealSize
            let natural =
                declared.width > 0
                ? declared.width : subview.sizeThatFits(.unspecified).width
            let width = min(max(natural, minWidth), maxWidth)

            let height =
                subview.isContentUnbounded
                ? declared.height
                : subview.sizeThatFits(
                    ProposedViewSize(width: width, height: nil)
                ).height

            if proposal.width != nil, subview.isContentReady {
                MainActor.assumeIsolated {
                    onIdealSize(CGSize(width: natural, height: height))
                }
            }

            return proposal.replacingUnspecifiedDimensions(
                by: CGSize(width: width, height: height)
            )
        }

        func placeSubviews(
            in bounds: CGRect,
            proposal: ProposedViewSize,
            subviews: Subviews,
            cache: inout ()
        ) {
            subviews.first?.place(
                at: bounds.origin,
                anchor: .topLeading,
                proposal: ProposedViewSize(bounds.size)
            )
        }
    }
}
