//
//  ContainerLogs.swift
//  Containers
//
//  Created by Axel Martinez on 10/2/26.
//

import ContainerSystem
import SwiftUI

struct ContainerLogs: View {
    private enum Source: String, CaseIterable, Identifiable {
        case output
        case boot

        var id: String { rawValue }

        var title: String {
            switch self {
            case .output: "Output"
            case .boot: "Boot"
            }
        }

        var filename: String {
            switch self {
            case .output: "stdio.log"
            case .boot: "vminitd.log"
            }
        }

        var emptyTitle: String {
            switch self {
            case .output: "No Output"
            case .boot: "No Boot Log"
            }
        }

        var emptyMessage: String {
            switch self {
            case .output:
                "Output will appear here when the container writes any"
            case .boot:
                "The console appears here once the container has been started"
            }
        }
    }

    @State private var source: Source = .output
    /// Lags `source` until the new log is read, so the empty message never names the wrong log.
    @State private var shownSource: Source = .output
    @State private var logs: String = ""
    @State private var hasLoaded: Bool = false
    @State private var isFollowing = true
    @State private var isAtEnd = true
    @State private var filter = ""

    var containerID: String

    private static let end = "end"

    /// Wider than any detail window, so the log always takes the full width.
    private static let idealWidth: CGFloat = 1_200

    var body: some View {
        VStack(spacing: 0) {
            if hasLoaded {
                bar

                Group {
                    if logs.isEmpty {
                        ContentUnavailableView {
                            Label(
                                shownSource.emptyTitle,
                                systemImage: "list.bullet.rectangle"
                            )
                        } description: {
                            Text(shownSource.emptyMessage)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        terminal
                    }
                }
                // Otherwise the window's animation crossfades the two logs.
                .transaction { $0.animation = nil }
            } else {
                Color.clear
            }
        }
        .contentReady(hasLoaded)
        // Unmeasured, so switching, filtering or emptying the log never resizes the window.
        .contentUnbounded()
        .contentIdealSize(CGSize(width: Self.idealWidth, height: 0))
        .task(id: source) {
            await streamLogs()
        }
    }

    private var bar: some View {
        ScopeBar(filter: $filter) {
            HStack(spacing: 2) {
                ForEach(Source.allCases) { source in
                    BarToggle(
                        source.title,
                        selection: $source,
                        value: source,
                        manner: .tab
                    )
                }
            }

            Divider()
                .frame(height: 12)
        } trailing: {
            BarToggle(
                title: "Tail",
                manner: .control,
                isOn: $isFollowing
            )
        }
    }

    private var shown: String {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else { return logs }

        return
            logs
            .components(separatedBy: .newlines)
            .filter { $0.localizedCaseInsensitiveContains(query) }
            .joined(separator: "\n")
    }

    private var terminal: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(shown)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)

                    Color.clear
                        .frame(height: 0)
                        .id(Self.end)
                }
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.visibleRect.maxY >= geometry.contentSize.height - 1
            } action: { _, atEnd in
                isAtEnd = atEnd

                if atEnd { isFollowing = true }
            }
            // Only the reader scrolling away turns Tail off; new text doesn't.
            .onScrollPhaseChange { oldPhase, newPhase in
                if oldPhase != .idle, newPhase == .idle {
                    isFollowing = isAtEnd
                }
            }
            .onChange(of: shown) {
                guard isFollowing else { return }

                proxy.scrollTo(Self.end, anchor: .bottom)
            }
            .onChange(of: isFollowing) {
                guard isFollowing else { return }

                withAnimation {
                    proxy.scrollTo(Self.end, anchor: .bottom)
                }
            }
        }
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.visible)
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private func replace(with text: String, of source: Source) {
        withTransaction(Transaction(animation: nil)) {
            logs = text
            shownSource = source
        }
    }

    private func streamLogs() async {
        let containerDir = UserDefaults.applicationDataRoot
            .appendingPathComponent("containers")
            .appendingPathComponent(containerID)

        let logFile = containerDir.appendingPathComponent(source.filename)

        if !FileManager.default.fileExists(atPath: logFile.path) {
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
        }

        guard let fileHandle = try? FileHandle(forReadingFrom: logFile) else {
            replace(with: "", of: source)
            hasLoaded = true
            return
        }

        // Read before replacing, so the empty message doesn't flash between logs.
        var initial = ""

        if let initialData = try? fileHandle.readToEnd(),
            let initialContent = String(data: initialData, encoding: .utf8)
        {
            initial = initialContent.trimmingCharacters(in: .newlines)
        }

        replace(with: initial, of: source)

        hasLoaded = true

        _ = try? fileHandle.seekToEnd()

        let stream = AsyncStream<String> { continuation in
            fileHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    // File truncated or handle closed
                    do {
                        _ = try fileHandle.seekToEnd()
                    } catch {
                        fileHandle.readabilityHandler = nil
                        continuation.finish()
                        return
                    }
                }
                if let newContent = String(data: data, encoding: .utf8),
                    !newContent.isEmpty
                {
                    continuation.yield(newContent)
                }
            }

            continuation.onTermination = { @Sendable _ in
                fileHandle.readabilityHandler = nil
                try? fileHandle.close()
            }
        }

        for await newContent in stream {
            if !logs.isEmpty {
                logs += newContent
            } else {
                logs = newContent.trimmingCharacters(in: .newlines)
            }
        }
    }
}
