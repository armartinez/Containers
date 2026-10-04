//
//  WindowResizer.swift
//  Containers
//
//  Created by Axel Martinez on 23/5/26.
//

import AppKit

final class ResizeConstrainer: NSObject, NSWindowDelegate {
    var constraints = WindowConstraints()
    /// Nonisolated for the forwarding below; delegate calls arrive on main.
    nonisolated(unsafe) weak var next: NSWindowDelegate?

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        var size =
            next?.windowWillResize?(sender, to: frameSize) ?? frameSize

        if constraints.widthIsFixed {
            size.width = sender.frame.width
        } else {
            size.width = min(
                max(size.width, constraints.minWidth),
                constraints.maxWidth
            )
        }

        if constraints.heightIsFixed {
            size.height = sender.frame.height
        }

        return size
    }

    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame: NSRect)
        -> NSRect
    {
        var frame = window.frame

        if !constraints.widthIsFixed {
            frame.size.width = min(defaultFrame.width, constraints.maxWidth)
        }

        if !constraints.heightIsFixed {
            frame.size.height = defaultFrame.height
        }
        frame.origin.y = window.frame.maxY - frame.height

        return frame
    }

    // AppKit checks `responds(to:)` before sending an optional delegate
    // method, so both are needed to forward the rest to SwiftUI.
    nonisolated override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || next?.responds(to: aSelector) == true
    }

    nonisolated override func forwardingTarget(for aSelector: Selector!) -> Any? {
        next
    }
}

struct WindowConstraints: Equatable {
    /// Set per axis when the window already shows everything on that axis:
    /// there is nothing a drag could reveal, so it is refused.
    var heightIsFixed = true
    var widthIsFixed = true
    var minWidth: CGFloat = 0
    var maxWidth: CGFloat = .greatestFiniteMagnitude

    var isFixed: Bool { heightIsFixed && widthIsFixed }
}

/// Animates the window height — the one step SwiftUI has no hook for.
@MainActor
final class WindowResizer {
    private weak var window: NSWindow?
    private var requestedSize: CGSize?
    private var requestedDuration: TimeInterval = 0
    private var constraints = WindowConstraints()
    private let constrainer = ResizeConstrainer()

    /// Deferred a turn: this runs inside the render pass mutating the
    /// window reenters. Replays a fit that lost the race to the window.
    func bind(to window: NSWindow?) {
        guard let window, window !== self.window else { return }
        self.window = window

        Task { @MainActor in
            guard self.window === window else { return }

            attachConstrainer(to: window)
            apply(constraints, to: window)

            if let size = requestedSize {
                await fit(size: size, duration: requestedDuration)
            }
        }
    }

    var visibleScreenHeight: CGFloat? {
        (window?.screen ?? NSScreen.main)?.visibleFrame.height
    }

    var visibleScreenWidth: CGFloat? {
        (window?.screen ?? NSScreen.main)?.visibleFrame.width
    }

    func setConstraints(_ constraints: WindowConstraints) {
        self.constraints = constraints
        constrainer.constraints = constraints

        Task { @MainActor in
            guard let window, self.constraints == constraints else {
                return
            }
            apply(constraints, to: window)
        }
    }

    private func apply(
        _ constraints: WindowConstraints,
        to window: NSWindow
    ) {
        // The style mask covers both axes at once, so a window resizable on
        // one of them keeps it and the delegate holds the other. A window
        // showing all of its content on both loses it, handle and all.
        if constraints.isFixed {
            window.styleMask.remove(.resizable)
        } else {
            window.styleMask.insert(.resizable)
        }

        window.collectionBehavior.remove(.fullScreenPrimary)
        window.collectionBehavior.insert(.fullScreenNone)

    }

    private func attachConstrainer(to window: NSWindow) {
        guard window.delegate !== constrainer else { return }

        constrainer.next = window.delegate
        window.delegate = constrainer
    }

    private func waitUntilOnScreen(_ window: NSWindow) async {
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(300))

        while !window.isVisible, ContinuousClock.now < deadline {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(8))
        }
    }

    /// Returns once the window has settled. Zero duration skips the animation.
    func fit(size: CGSize, duration: TimeInterval) async {
        guard size.height > 0 else { return }
        requestedSize = size
        requestedDuration = duration

        guard let window else { return }

        // An off-screen window has nothing to animate, so it would snap.
        if duration > 0, !window.isVisible {
            await waitUntilOnScreen(window)
        }

        // Convert through the window: contentView and frame disagree while an
        // earlier resize is still animating.
        var contentRect = window.contentRect(forFrameRect: window.frame)

        // Only contentLayoutRect is the view's, so add the toolbar strip.
        let chrome = contentRect.height - window.contentLayoutRect.height
        let target = CGSize(width: size.width, height: size.height + chrome)

        guard
            abs(contentRect.height - target.height) > 0.5
                || abs(contentRect.width - target.width) > 0.5
        else { return }

        contentRect.size = target
        var frame = window.frameRect(forContentRect: contentRect)

        frame.origin.y = window.frame.maxY - frame.height
        frame.origin.x = window.frame.midX - frame.width / 2

        guard window.isVisible, duration > 0 else {
            window.setFrame(frame, display: false)
            return
        }

        // TODO: A web-view tab logs "NSHostingView is being laid out
        // reentrantly" each tick — harmless; duration 0 silences it.
        await withCheckedContinuation { continuation in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(
                    name: .easeInEaseOut
                )
                window.animator().setFrame(frame, display: true)
            } completionHandler: {
                continuation.resume()
            }
        }
    }
}
