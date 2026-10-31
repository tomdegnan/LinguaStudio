import Foundation

/// Tokenizes a segment target `mrk` tree into protected tag tokens and editable text gaps.
/// Editing only mutates gap text; tag structure is re-applied surgically onto the live DOM.
public final class TagPlan {

    public enum Action {
        case open(XMLElement)
        case close
        case empty(XMLNode)
    }

    public private(set) var tokens: [String] = []
    public private(set) var actions: [Action] = []
    public private(set) var gaps: [String] = [""]
    /// True when the corresponding gap sits inside an existing revision marker.
    public private(set) var revisionGaps: [Bool] = [false]

    public let root: XMLElement

    public init(_ root: XMLElement) {
        self.root = root
        for child in root.children ?? [] {
            visit(child, inRevision: false)
        }
    }

    private func appendToken(_ value: String, _ action: Action, _ inRevision: Bool) {
        tokens.append(value)
        actions.append(action)
        gaps.append("")
        revisionGaps.append(inRevision)
    }

    private func visit(_ node: XMLNode, inRevision: Bool) {
        if node.kind == .text {
            gaps[gaps.count - 1] += node.stringValue ?? ""
            if inRevision {
                revisionGaps[revisionGaps.count - 1] = true
            }
            return
        }

        guard let element = node as? XMLElement else {
            appendToken("⟦\(tokens.count + 1):node⟧", .empty(node), inRevision)
            return
        }

        let mtype = element.attribute(forName: "mtype")?.stringValue ?? ""
        let revised = inRevision || mtype.hasPrefix("x-sdl-")
        let number = tokens.count + 1
        let local = xmlLocalName(element)
        let idSuffix = element.attribute(forName: "id")?.stringValue.map { ":" + $0 } ?? ""
        let label = local + idSuffix

        if (element.children ?? []).isEmpty {
            appendToken("⟦\(number):\(label)/⟧", .empty(element), inRevision)
            return
        }

        appendToken("⟦\(number):\(label)⟧", .open(element), revised)
        for child in element.children ?? [] {
            visit(child, inRevision: revised)
        }
        appendToken("⟦/\(number)⟧", .close, inRevision)
    }

    /// Flattened editable string with opaque tag tokens.
    public var text: String {
        var result = gaps[0]
        for i in tokens.indices {
            result += tokens[i] + gaps[i + 1]
        }
        return result
    }

    /// Split an edited string back into gap strings, verifying tokens were not altered.
    public func split(_ edited: String) throws -> [String] {
        var remaining = edited[...]
        var parts: [String] = []

        for token in tokens {
            guard let range = remaining.range(of: token) else {
                throw LinguaError.message(
                    "Tags cannot be deleted or altered. Undo changes to protected blue tags. / 标签不能删除或改动。"
                )
            }
            let before = String(remaining[..<range.lowerBound])
            guard !before.contains("⟦"), !before.contains("⟧") else {
                throw LinguaError.message("Tag order was changed. / 标签顺序已改变。")
            }
            parts.append(before)
            remaining = remaining[range.upperBound...]
        }

        guard !remaining.contains("⟦"), !remaining.contains("⟧") else {
            throw LinguaError.message("Unrecognized tag markers. / 出现无法识别的标签。")
        }
        parts.append(String(remaining))
        return parts
    }

    /// Apply edited gap text onto `root` by rebuilding children while copying original tag elements.
    /// When `tracking` is true, text diffs become x-sdl-added / x-sdl-deleted markers.
    public func apply(
        _ edited: String,
        tracking: Bool,
        document: XMLDocument,
        author: String
    ) throws {
        var parts = try split(edited)

        // Track Changes OFF: never block the UI with an error — silently keep the
        // original revision-gap text so flush / segment switch always succeeds.
        if !tracking {
            for i in parts.indices where revisionGaps[i] && parts[i] != gaps[i] {
                parts[i] = gaps[i]
            }
        }

        let result = root.copy() as! XMLElement
        result.setChildren([])
        var stack: [XMLElement] = [result]

        for i in parts.indices {
            let parent = stack.last!

            if revisionGaps[i] {
                // In-place update inside x-sdl-added / x-sdl-deleted (tracking ON only
                // reaches here with changed text; OFF path was sanitized above).
                if !parts[i].isEmpty {
                    parent.addChild(XMLNode.text(withStringValue: parts[i]) as! XMLNode)
                }
            } else if tracking && parts[i] != gaps[i] {
                try appendTrackedDiff(
                    parent: parent,
                    oldText: gaps[i],
                    newText: parts[i],
                    document: document,
                    author: author
                )
            } else if !parts[i].isEmpty {
                parent.addChild(XMLNode.text(withStringValue: parts[i]) as! XMLNode)
            }

            guard i < actions.count else { continue }

            switch actions[i] {
            case .open(let original):
                let copy = original.copy() as! XMLElement
                copy.setChildren([])
                parent.addChild(copy)
                stack.append(copy)
            case .close:
                _ = stack.popLast()
            case .empty(let original):
                parent.addChild(original.copy() as! XMLNode)
            }
        }

        let children = (result.children ?? []).map { $0.copy() as! XMLNode }
        root.setChildren(children)
    }

    private func appendTrackedDiff(
        parent: XMLElement,
        oldText: String,
        newText: String,
        document: XMLDocument,
        author: String
    ) throws {
        let oldChars = Array(oldText)
        let newChars = Array(newText)

        var prefix = 0
        while prefix < min(oldChars.count, newChars.count),
              oldChars[prefix] == newChars[prefix] {
            prefix += 1
        }

        var suffix = 0
        while suffix < min(oldChars.count - prefix, newChars.count - prefix),
              oldChars[oldChars.count - 1 - suffix] == newChars[newChars.count - 1 - suffix] {
            suffix += 1
        }

        // Avoid peeling a shared CJK character into the common suffix when both sides
        // also changed (你好→您好 was becoming del(你)+add(您)+好). Pull leading CJK
        // of the shared suffix back into the replaced region. Whitespace stays shared.
        while suffix > 0 {
            let candidate = oldChars[oldChars.count - suffix]
            let removedCount = oldChars.count - prefix - suffix
            let addedCount = newChars.count - prefix - suffix
            guard removedCount > 0, addedCount > 0, isCJKCharacter(candidate) else { break }
            suffix -= 1
        }

        if prefix > 0 {
            let kept = String(oldChars.prefix(prefix))
            parent.addChild(XMLNode.text(withStringValue: kept) as! XMLNode)
        }

        let removed = String(oldChars[prefix..<(oldChars.count - suffix)])
        let added = String(newChars[prefix..<(newChars.count - suffix)])

        if !removed.isEmpty {
            parent.addChild(
                try RevisionFactory.makeMarker(
                    text: removed,
                    deleted: true,
                    document: document,
                    author: author
                )
            )
        }
        if !added.isEmpty {
            parent.addChild(
                try RevisionFactory.makeMarker(
                    text: added,
                    deleted: false,
                    document: document,
                    author: author
                )
            )
        }

        if suffix > 0 {
            let kept = String(oldChars.suffix(suffix))
            parent.addChild(XMLNode.text(withStringValue: kept) as! XMLNode)
        }
    }
}

/// Han / Hangul / kana — used so track-change diffs do not split a CJK compound across markers.
func isCJKCharacter(_ ch: Character) -> Bool {
    for scalar in ch.unicodeScalars {
        switch scalar.value {
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
             0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFF00...0xFFEF:
            return true
        default:
            break
        }
    }
    return false
}
