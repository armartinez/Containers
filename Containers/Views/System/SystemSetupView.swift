//
//  SystemSetupView.swift
//  Containers
//
//  Created by Axel Martinez on 12/09/2026.
//

import ContainersCore
import SwiftUI

/// First-run setup (fetching the init image, downloading the kernel) on its own sheet.
/// A start already under way when it opens is only watched, not restarted.
struct SystemSetupView: View {
    /// Lets the presenter keep the sheet from reopening while the cancel unwinds.
    var onCancel: () -> Void = {}

    @Environment(ContainerSystem.self) private var containerSystem
    @Environment(SystemActions.self) private var systemActions
    @Environment(\.dismiss) private var dismiss

    @SwiftUI.State private var failure: ErrorAlert?
    @SwiftUI.State private var progress: ProgressObserver?
    @SwiftUI.State private var isConfirmingKernel = false

    var body: some View {
        Group {
            if isConfirmingKernel {
                kernelSheet
            } else {
                setupSheet
            }
        }
        // Escape can't dismiss work in progress.
        .interactiveDismissDisabled(failure == nil)
        .onChange(of: containerSystem.setupProgress, initial: true) { _, setupProgress in
            progress = setupProgress.map(ProgressObserver.init)
        }
        .task {
            switch containerSystem.status {
            case .running, .readOnly:
                dismiss()
            // Already starting: just watch it.
            case .starting:
                break
            default:
                if containerSystem.needsKernelConfirmation {
                    isConfirmingKernel = true
                } else {
                    setup()
                }
            }
        }
        .onChange(of: containerSystem.status) { _, status in
            switch status {
            // A cancelled start ends stopped; the dashboard shows that.
            case .notStarted where containerSystem.needsKernelConfirmation:
                isConfirmingKernel = true
            case .running, .notStarted, .readOnly:
                dismiss()
            case .failed:
                failure = containerSystem.startupError.map {
                    ErrorAlert("Containers Couldn’t Be Set Up", error: $0)
                }
            default:
                break
            }
        }
    }

    private static let failureMarkBand: CGFloat = 96

    /// The progress and the failure are drawn over the content, so the sheet keeps a size of its own for them.
    private var setupSheet: some View {
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
            content: { setupProgress },
            actions: {
                Spacer()

                if failure == nil {
                    Button {
                        cancelSetup()
                    } label: {
                        Text("Cancel")
                            .frame(minWidth: .sheetButtonLabelWidth)
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                } else {
                    Button {
                        dismiss()
                    } label: {
                        Text("Close")
                            .frame(minWidth: .sheetButtonLabelWidth)
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)

                    Button {
                        setup()
                    } label: {
                        Text("Try Again")
                            .frame(minWidth: .sheetButtonLabelWidth)
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
    }

    /// Sized to its text, as a question.
    private var kernelSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            kernelConfirmation

            HStack(spacing: 8) {
                Spacer()

                Button {
                    cancelSetup()
                } label: {
                    Text("Cancel")
                        .frame(minWidth: .sheetButtonLabelWidth)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                Button {
                    setup(installingKernel: true)
                } label: {
                    Text("Install")
                        .frame(minWidth: .sheetButtonLabelWidth)
                }
                .defaultAction(enabled: true)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private var setupProgress: some View {
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

    private var kernelConfirmation: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Install the Recommended Default Kernel?")
                    .font(.headline)

                Text("No default kernel is configured. Containers installs the recommended default kernel from:")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let url = ContainerSystem.defaultKernelURL {
                    Text(url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setup(installingKernel: Bool = false) {
        failure = nil
        isConfirmingKernel = false
        systemActions.dismissKernelQuestion()
        Task {
            // Failures arrive as a `.failed` status, which the sheet already watches.
            try? await containerSystem.start(appRoot: UserDefaults.systemDataRoot, installingKernel: installingKernel)
        }
    }

    /// Cancels the system's start, whether or not this sheet began it.
    private func cancelSetup() {
        containerSystem.cancelStart()
        systemActions.dismissKernelQuestion()
        onCancel()
        dismiss()
    }
}
