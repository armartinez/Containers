//
//  CreateView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/07/05.
//

import SwiftUI

struct CreateView<
    Content: View, Actions: View, TabBar: View, Failure: View
>: View {
    let title: String
    let error: Binding<ErrorAlert?>
    let isProcessing: Bool
    let isFailed: Bool
    let progressTitle: String?
    let width: CGFloat
    let height: CGFloat
    let showsHeader: Bool
    let contentAlignment: Alignment
    let scrollsContent: Bool
    let showsFooterDivider: Bool
    let contentID: AnyHashable?
    let contentTransition: AnyTransition
    let contentPadding: CGFloat
    let contentTitle: String?
    let contentTitleRule: Bool
    let tabBar: TabBar
    let content: Content
    let actions: Actions
    let failure: Failure

    init(
        title: String,
        error: Binding<ErrorAlert?> = .constant(nil),
        isProcessing: Bool = false,
        isFailed: Bool = false,
        progressTitle: String? = nil,
        width: CGFloat,
        height: CGFloat,
        showsHeader: Bool = true,
        contentAlignment: Alignment = .topLeading,
        scrollsContent: Bool = false,
        showsFooterDivider: Bool = true,
        contentPadding: CGFloat = 20,
        contentID: AnyHashable? = nil,
        contentTransition: AnyTransition = .identity,
        contentTitle: String? = nil,
        contentTitleRule: Bool = false,
        @ViewBuilder tabBar: () -> TabBar = { EmptyView() },
        @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder failure: () -> Failure = { EmptyView() }
    ) {
        self.title = title
        self.error = error
        self.isProcessing = isProcessing
        self.isFailed = isFailed
        self.progressTitle = progressTitle
        self.width = width
        self.height = height
        self.showsHeader = showsHeader
        self.contentAlignment = contentAlignment
        self.scrollsContent = scrollsContent
        self.showsFooterDivider = showsFooterDivider
        self.contentPadding = contentPadding
        self.contentID = contentID
        self.contentTransition = contentTransition
        self.contentTitle = contentTitle
        self.contentTitleRule = contentTitleRule
        self.tabBar = tabBar()
        self.content = content()
        self.actions = actions()
        self.failure = failure()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Working, the sheet is only its progress and the buttons that
            // answer it: the title and the steps it names are gone.
            if showsHeader && !isProcessing {
                Text(title)
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
            }

            if TabBar.self != EmptyView.self && !isProcessing {
                Divider()

                tabBar
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity)
                    .frame(height: .barHeight)
                    .background(Color(nsColor: .controlBackgroundColor))

                Divider()
            }

            contentArea
                // Centred on what is left above the buttons rather than on the
                // whole sheet, so the footer's height is taken off the room
                // being centred in and the mark rides up by half of it. What
                // stands in for a step is read here — the progress, and the
                // failure that may end it — so the two land in one place.
                .overlay {
                    if isProcessing {
                        progressStatus
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    } else if isFailed {
                        failure
                    }
                }

            if showsFooterDivider {
                Divider()
            }

            footer
        }
        .frame(width: width, height: height)
        .interactiveDismissDisabled(isProcessing)
        .errorAlert(error)
    }

    private var contentArea: some View {
        // The header sits outside the transition: it belongs to the sheet
        // rather than to the step, so it does not slide or fade with one.
        VStack(alignment: .leading, spacing: 0) {
            // The step change animates the content across; the title going
            // with it is the sheet's furniture moving, so it changes instantly.
            Group {
                if let contentTitle {
                    Text(contentTitle)
                        .padding(.horizontal, contentPadding)
                        .padding(.top, contentPadding)
                        .padding(.bottom, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Ruled off directly under the title, so the rule belongs
                    // to it rather than to whatever the step puts below.
                    if contentTitleRule {
                        Divider()
                    }
                }
            }
            .transaction { $0.animation = nil }

            ZStack(alignment: contentAlignment) {
                contentContainer
                    .id(contentID)
                    .transition(contentTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .opacity(isProcessing || isFailed ? 0 : 1)
    }

    @ViewBuilder
    private var contentContainer: some View {
        if scrollsContent {
            ScrollView {
                content
                    .padding(contentPadding)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            content
                .padding(contentPadding)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: contentAlignment
                )
        }
    }

    /// The spinner sits on the sheet's centre line, and what it is doing
    /// hangs under it as an overlay: an overlay takes no part in laying out
    /// what it is attached to, so the writing cannot carry the spinner up
    /// however many lines of it there are.
    private var progressStatus: some View {
        ProgressView()
            .overlay(alignment: .bottom) {
                if let progressTitle {
                    Text(progressTitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(width: width - 40)
                        // Hung from the spinner's foot rather than sharing its
                        // bottom edge, which is what puts the writing below it.
                        .alignmentGuide(VerticalAlignment.bottom) { _ in
                            -CGFloat.sheetMarkSpacing
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            actions
        }
        .controlSize(.regular)
        .padding(16)
        // The step change animates the content across; the buttons swapping
        // with it reads as a glitch, so they change instantly.
        .transaction { $0.animation = nil }
    }
}

/// The tabs across the top of a sheet, drawn as the tabs over a log are.
struct CreateViewTabBar<Tab: Hashable & CaseIterable & RawRepresentable>: View
where Tab.AllCases: RandomAccessCollection, Tab.RawValue == String {
    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(Tab.allCases), id: \.self) { tab in
                BarToggle(
                    tab.rawValue,
                    selection: $selection,
                    value: tab,
                    manner: .segment
                )
            }
        }
    }
}
