//
//  ErrorAlert.swift
//  Containers
//
//  Created by Axel Martinez on 24/08/2026.
//

import AppKit
import ContainerizationError
import SwiftUI

/// What went wrong, put the way an alert is meant to put it: a title naming
/// the problem, a sentence that can be acted on, and the raw error kept out of
/// the way until it is asked for.
struct ErrorAlert: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let details: String?

    init(_ title: String, message: String, details: String? = nil) {
        self.title = title
        self.message = message
        self.details = details
    }

    /// The title says what failed; the error says why, in the only part of it
    /// written for a person to read.
    ///
    /// - Parameters showsDetails: Whether the raw error is kept behind a
    ///   disclosure. Turn it off where the message is the whole account and
    ///   there is nothing worth unfolding.
    init(_ title: String, error: Error, showsDetails: Bool = true) {
        let raw = String(describing: error)
        let message = Self.message(for: error)

        self.init(
            title,
            message: message,
            details: showsDetails && raw != message ? raw : nil
        )
    }

    static func == (lhs: ErrorAlert, rhs: ErrorAlert) -> Bool {
        lhs.id == rhs.id
    }

    /// A `ContainerizationError` describes itself as `code: "message"`, of
    /// which only the message was written to be read.
    private static func message(for error: Error) -> String {
        guard let error = error as? ContainerizationError else {
            return error.localizedDescription
        }

        let message = error.message.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return message.isEmpty ? error.localizedDescription : message
    }
}

extension View {
    /// Presents errors as the alert AppKit builds: the app icon, centred text,
    /// and an accent-filled default button, none of which SwiftUI's own alert
    /// draws on macOS.
    func errorAlert(_ alert: Binding<ErrorAlert?>) -> some View {
        modifier(ErrorAlertModifier(alert: alert))
    }
}

private struct ErrorAlertModifier: ViewModifier {
    @Binding var alert: ErrorAlert?

    @SwiftUI.State private var window: NSWindow?

    func body(content: Content) -> some View {
        content
            .background(AlertWindowBinder(window: $window))
            .onChange(of: alert) { _, alert in
                guard let alert else { return }
                present(alert)
            }
    }

    private func present(_ alert: ErrorAlert) {
        let nsAlert = NSAlert()
        nsAlert.alertStyle = .warning
        nsAlert.messageText = alert.title
        nsAlert.informativeText = alert.message
        nsAlert.addButton(withTitle: "OK")

        if let details = alert.details {
            nsAlert.accessoryView = ErrorDetailsView(
                details: details,
                alert: nsAlert
            )
        }

        let dismiss: (NSApplication.ModalResponse) -> Void = { _ in
            self.alert = nil
        }

        if let window, window.isVisible {
            nsAlert.beginSheetModal(for: window, completionHandler: dismiss)
        } else {
            dismiss(nsAlert.runModal())
        }
    }
}

/// The raw error, behind a disclosure so that it is there for a bug report
/// without being the first thing read.
private final class ErrorDetailsView: NSView {
    private let disclosure = NSButton()
    private let scrollView = NSScrollView()
    private unowned let alert: NSAlert

    private static let width: CGFloat = 380
    private static let headerHeight: CGFloat = 18
    private static let detailsHeight: CGFloat = 120

    init(details: String, alert: NSAlert) {
        self.alert = alert

        super.init(
            frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.headerHeight)
        )

        disclosure.bezelStyle = .disclosure
        disclosure.setButtonType(.onOff)
        disclosure.title = ""
        disclosure.target = self
        disclosure.action = #selector(toggleDetails)
        disclosure.frame = NSRect(x: 0, y: 0, width: 16, height: 16)

        let label = NSTextField(labelWithString: "Details")
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 20, y: 0, width: 200, height: 16)

        let text = NSTextView()
        text.string = details
        text.isEditable = false
        text.drawsBackground = false
        text.font = .monospacedSystemFont(
            ofSize: NSFont.smallSystemFontSize,
            weight: .regular
        )

        scrollView.documentView = text
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.isHidden = true
        scrollView.frame = NSRect(
            x: 0,
            y: Self.headerHeight + 4,
            width: Self.width,
            height: Self.detailsHeight
        )

        addSubview(disclosure)
        addSubview(label)
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) unavailable")
    }

    @objc private func toggleDetails() {
        let isExpanded = disclosure.state == .on

        scrollView.isHidden = !isExpanded
        frame = NSRect(
            x: 0,
            y: 0,
            width: Self.width,
            height: isExpanded
                ? Self.headerHeight + 4 + Self.detailsHeight
                : Self.headerHeight
        )

        alert.layout()
    }
}

/// The window the alert hangs off, so it arrives as a sheet on the window the
/// error came from rather than in the middle of the screen.
private struct AlertWindowBinder: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        BindingView { window = $0 }
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    /// Reports on `viewDidMoveToWindow` rather than in `updateNSView`, which
    /// can run before the view has a window and never again after.
    private final class BindingView: NSView {
        private let onWindow: (NSWindow?) -> Void

        init(onWindow: @escaping (NSWindow?) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) unavailable")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            let window = self.window
            MainActor.assumeIsolated { onWindow(window) }
        }
    }
}
