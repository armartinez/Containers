//
//  InspectView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/06/06.
//

import AppKit
import Foundation
import SwiftUI

struct InspectView: View {
    private let root: JSONNode?
    /// `nil` while the caller is still loading. The scroll view shows anyway:
    /// with none beneath it, the toolbar draws a hard line instead of its edge
    /// effect.
    private let json: String?

    /// The tree's natural size. A scroll view reports its viewport, not its
    /// content, so the tree is measured here and passed up.
    @State private var treeSize: CGSize = .zero

    init(json: String?) {
        self.json = json
        self.root = json.flatMap(JSONTree.build)
    }

    init<Value: Encodable>(value: Value?) {
        self.init(json: value.map(InspectJSONEncoder.encode))
    }

    /// Called during layout, so the state write is deferred. The loading
    /// placeholder isn't measured, or the window would fit to it first.
    private func measureTree(size: CGSize) {
        guard
            json != nil,
            size.width > 0,
            abs(treeSize.width - size.width) > 0.5
                || abs(treeSize.height - size.height) > 0.5
        else { return }

        Task { @MainActor in treeSize = size }
    }

    var body: some View {
        // A scroll view centres content smaller than itself. Growing the tree
        // to the viewport keeps it top-leading; a scroll axis proposes no
        // size, so the viewport comes from a GeometryReader.
        GeometryReader { viewport in
            ScrollView([.vertical, .horizontal]) {
                MeasuredSize(onSize: measureTree) {
                    Group {
                        if let root {
                            JSONNodeView(node: root)
                        } else if let json {
                            // Not valid JSON: show the raw text.
                            Text(json)
                                .font(JSONStyle.font)
                                .textSelection(.enabled)
                        } else {
                            // Still loading; hidden by the window until ready.
                            // Not empty, or the scroll view doesn't count as one.
                            Color.clear
                                .frame(width: 1, height: 1)
                        }
                    }
                    // Lines scroll rather than wrap, so long values like digests stay whole.
                    .fixedSize()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(
                        minWidth: viewport.size.width,
                        minHeight: viewport.size.height,
                        alignment: .topLeading
                    )
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .contentIdealSize(treeSize)
        // The size arrives a turn after the first layout. Fitting earlier
        // resizes the window in two animations instead of one.
        .contentReady(json != nil && treeSize != .zero)
        // JSON can be any length, so the window bounds the tab and it scrolls.
        .contentUnbounded()
    }
}

/// Reports its content's natural size while laying it out at the proposed
/// size, in one pass so the tree isn't measured twice.
private struct MeasuredSize: Layout {
    let onSize: @MainActor @Sendable (CGSize) -> Void

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let subview = subviews.first else { return .zero }

        let natural = subview.sizeThatFits(.unspecified)
        MainActor.assumeIsolated { onSize(natural) }

        return proposal.replacingUnspecifiedDimensions(by: natural)
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

enum InspectJSONEncoder {
    static func encode<Value: Encodable>(_ value: Value) -> String {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [
                .prettyPrinted,
                .withoutEscapingSlashes,
            ]

            let data = try encoder.encode(value)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return
                "{\n  \"error\" : \"Unable to encode inspect JSON: \(error.localizedDescription)\"\n}"
        }
    }
}

// MARK: - Tree

private struct JSONNodeView: View {
    let node: JSONNode

    @State private var isExpanded = true

    var body: some View {
        switch node.value {
        case .object(let children):
            branch(children, open: "{", close: "}")
        case .array(let children):
            branch(children, open: "[", close: "]")
        case .leaf(let text, let role):
            row(key + JSONRun.text(text, role))
        }
    }

    private func branch(
        _ children: [JSONNode],
        open: String,
        close: String
    ) -> some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(children) { JSONNodeView(node: $0) }
            }
            // Outside a List, a DisclosureGroup doesn't indent its content.
            .padding(.leading, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            row(
                key
                    + JSONRun.text(open, .punctuation)
                    + JSONRun.text(summary(children), .muted)
                    + JSONRun.text(close, .punctuation)
            )
        }
    }

    /// One `Text` per row, coloured by attributes, so selection spans the whole line.
    private func row(_ attributed: AttributedString) -> some View {
        Text(attributed)
            .font(JSONStyle.font)
            .textSelection(.enabled)
    }

    private func summary(_ children: [JSONNode]) -> String {
        switch children.count {
        case 0: " "
        case 1: " 1 item "
        default: " \(children.count) items "
        }
    }

    private var key: AttributedString {
        guard let key = node.key else { return AttributedString() }
        return JSONRun.text(key, .key) + JSONRun.text(" : ", .punctuation)
    }
}

private enum JSONRun {
    static func text(_ string: String, _ role: JSONRole) -> AttributedString {
        var run = AttributedString(string)
        run.foregroundColor = role.color
        return run
    }
}

private enum JSONStyle {
    static let font = Font.system(size: 12, design: .monospaced)
}

private enum JSONRole {
    case key, string, number, boolean, null, punctuation, muted

    var color: Color {
        switch self {
        case .muted: .secondary
        case .key: .init(nsColor: .inspect(light: 0x9B4D00, dark: 0xF0B35A))
        case .string: .init(nsColor: .inspect(light: 0x0A7F32, dark: 0x7BD88F))
        case .number: .init(nsColor: .inspect(light: 0x1769C2, dark: 0x80BFFF))
        case .boolean: .init(nsColor: .inspect(light: 0x8D35B2, dark: 0xD59CFF))
        case .null: .init(nsColor: .inspect(light: 0x777777, dark: 0xA0A0A0))
        case .punctuation: .secondary
        }
    }
}

private struct JSONNode: Identifiable {
    enum Value {
        case object([JSONNode])
        case array([JSONNode])
        case leaf(String, JSONRole)
    }

    /// The node's path, stable across re-parses so disclosure state survives a rebuild.
    let id: String
    /// Quoted, as it would be written. `nil` for array elements and the root.
    let key: String?
    let value: Value
}

// MARK: - Parsing

private enum JSONTree {
    static func build(_ json: String) -> JSONNode? {
        guard
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
            )
        else { return nil }

        return JSONNode(id: "", key: nil, value: value(of: object, path: ""))
    }

    private static func value(of object: Any, path: String) -> JSONNode.Value {
        switch object {
        case let dictionary as [String: Any]:
            // Sorted, since `JSONSerialization` returns keys unordered.
            .object(
                dictionary.sorted { $0.key < $1.key }.map { key, child in
                    let childPath = "\(path)/\(key)"
                    return JSONNode(
                        id: childPath,
                        key: quoted(key),
                        value: value(of: child, path: childPath)
                    )
                }
            )
        case let array as [Any]:
            .array(
                array.enumerated().map { offset, child in
                    let childPath = "\(path)/\(offset)"
                    return JSONNode(
                        id: childPath,
                        key: nil,
                        value: value(of: child, path: childPath)
                    )
                }
            )
        case let string as String:
            .leaf(quoted(string), .string)
        case let number as NSNumber:
            CFGetTypeID(number) == CFBooleanGetTypeID()
                ? .leaf(number.boolValue ? "true" : "false", .boolean)
                : .leaf(number.description, .number)
        default:
            .leaf("null", .null)
        }
    }

    /// Re-escapes a decoded string so the row shows it as written in the JSON.
    private static func quoted(_ string: String) -> String {
        var quoted = "\""

        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": quoted += "\\\""
            case "\\": quoted += "\\\\"
            case "\n": quoted += "\\n"
            case "\r": quoted += "\\r"
            case "\t": quoted += "\\t"
            case _ where scalar.value < 0x20:
                quoted += String(format: "\\u%04x", scalar.value)
            default: quoted.unicodeScalars.append(scalar)
            }
        }

        return quoted + "\""
    }
}

extension NSColor {
    /// Resolved at draw time, so the colours follow the system appearance.
    fileprivate static func inspect(light: Int, dark: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark =
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        }
    }

    fileprivate convenience init(rgb: Int) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
