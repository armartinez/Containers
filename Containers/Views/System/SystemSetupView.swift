//
//  SystemSetupView.swift
//  Containers
//
//  Created by Axel Martinez on 12/09/2026.
//

import ContainerSystem
import SwiftUI

/// First-run setup (fetching the init image, downloading the kernel) on its own sheet.
/// A start already under way when it opens is only watched, not restarted.
struct SystemSetupView: View {
    /// Lets the presenter keep the sheet from reopening while the cancel unwinds.
    var onCancel: () -> Void = {}

    @Environment(SystemManager.self) private var system
    @Environment(\.dismiss) private var dismiss

    @SwiftUI.State private var failure: ErrorAlert?
    @SwiftUI.State private var progress: ProgressObserver?

    var body: some View {
        CreateView(
            title: "Set Up Containers",
            isFailed: failure != nil,
            width: 520,
            // The failure's disclosure needs more room than the progress.
            height: failure == nil ? 340 : 460,
            showsHeader: false,
            contentAlignment: .center,
            showsFooterDivider: false,
            contentPadding: 24,
            content: {
                setUpProgress
            },
            actions: {
                Spacer()

                if failure == nil {
                    Button {
                        cancelSetup()
                    } label: {
                        Text("Cancel")
                            .frame(width: .sheetButtonLabelWidth)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        dismiss()
                    } label: {
                        Text("Close")
                            .frame(width: .sheetButtonLabelWidth)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        setUp()
                    } label: {
                        Text("Try Again")
                            .frame(width: .sheetButtonLabelWidth)
                    }
                    .defaultAction(enabled: true)
                }
            },
            failure: {
                if let failure {
                    // Pinned near the top, so the text below the mark has the
                    // sheet's height to grow into.
                    CreateImageFailure(failure: failure)
                        .frame(height: Self.failureMarkBand)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        )
        // Escape can't dismiss work in progress.
        .interactiveDismissDisabled(failure == nil)
        .onChange(of: system.setupProgress, initial: true) { _, setupProgress in
            progress = setupProgress.map(ProgressObserver.init)
        }
        .task {
            switch system.status {
            case .running:
                dismiss()
            // Already starting: just watch it.
            case .starting:
                break
            default:
                setUp()
            }
        }
        .onChange(of: system.status) { _, status in
            switch status {
            // A cancelled start ends stopped; the dashboard shows that.
            case .running, .notStarted:
                dismiss()
            case .failed:
                failure = system.startupError.map {
                    ErrorAlert("Containers Couldn’t Be Set Up", error: $0)
                }
            default:
                break
            }
        }
    }

    private static let failureMarkBand: CGFloat = 96

    private var setUpProgress: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 8) {
                Text(progressTitle)
                    .font(.headline)
                    .lineLimit(1)

                progressBar
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Determinate when the step reports a total, indeterminate otherwise.
    @ViewBuilder
    private var progressBar: some View {
        if let fraction = progress?.fractionCompleted {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
        } else {
            ProgressView()
                .progressViewStyle(.linear)
        }
    }

    private var progressTitle: String {
        guard let step = progress?.localizedDescription, !step.isEmpty else {
            return "Setting up the container system…"
        }

        return step + "…"
    }

    private func setUp() {
        failure = nil
        Task {
            // Failures arrive as a `.failed` status, which the sheet already watches.
            try? await system.start(appRoot: UserDefaults.applicationDataRoot)
        }
    }

    /// Cancels the system's start, whether or not this sheet began it.
    private func cancelSetup() {
        system.cancelStart()
        onCancel()
        dismiss()
    }
}
