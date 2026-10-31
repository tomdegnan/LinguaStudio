import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Basic inline formats Lingua Studio can apply (Trados-like bold / italic / underline).
public enum InlineFormatKind: String, CaseIterable, Sendable {
    case bold
    case italic
    case underline
    case superscript
    case `subscript`

    public var menuTitle: String {
        switch self {
        case .bold: return "粗体"
        case .italic: return "斜体"
        case .underline: return "下划线"
        case .superscript: return "上标"
        case .subscript: return "下标"
        }
    }

    var preferredTagID: String {
        switch self {
        case .bold: return "ls-b"
        case .italic: return "ls-i"
        case .underline: return "ls-u"
        case .superscript: return "ls-sup"
        case .subscript: return "ls-sub"
        }
    }

    var preferredFmtID: String {
        switch self {
        case .bold: return "ls-fmt-b"
        case .italic: return "ls-fmt-i"
        case .underline: return "ls-fmt-u"
        case .superscript: return "ls-fmt-sup"
        case .subscript: return "ls-fmt-sub"
        }
    }

    var fmtKey: String {
        switch self {
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .underline: return "Underline"
        case .superscript, .subscript: return "TextPosition"
        }
    }

    var fmtValue: String {
        switch self {
        case .bold, .italic, .underline: return "True"
        case .superscript: return "Superscript"
        case .subscript: return "Subscript"
        }
    }

    var cfOpen: String {
        switch self {
        case .bold: return "<cf bold=True>"
        case .italic: return "<cf italic=True>"
        case .underline: return "<cf underline=single>"
        case .superscript: return "<cf superscript=True>"
        case .subscript: return "<cf subscript=True>"
        }
    }

    /// True when `format` is a pure match for this kind (no other BIU/position flags).
    public func matches(_ format: TextFormat) -> Bool {
        switch self {
        case .bold:
            return format.bold == true && format.italic != true && format.underline != true
                && format.position == nil
        case .italic:
            return format.italic == true && format.bold != true && format.underline != true
                && format.position == nil
        case .underline:
            return format.underline == true && format.bold != true && format.italic != true
                && format.position == nil
        case .superscript:
            return format.position == .superscript
                && format.bold != true && format.italic != true && format.underline != true
        case .subscript:
            return format.position == .subscript
                && format.bold != true && format.italic != true && format.underline != true
        }
    }
}

/// Ensures SDL `fmt-defs` / `tag-defs` exist and wraps a draft UTF-16 range in `<g id>`.
public enum FormatTagSupport {

    /// Resolve a tag id for `kind` in the first `<file>`: reuse an existing pure match, else create `ls-*`.
    @discardableResult
    public static func ensureTagID(
        for kind: InlineFormatKind,
        in document: XMLDocument
    ) throws -> String {
        guard let root = document.rootElement() else {
            throw LinguaError.message("XML has no root element. / XML 没有根节点。")
        }
        let files = (root.children ?? [])
            .compactMap { $0 as? XMLElement }
            .filter { xmlLocalName($0) == "file" }
        guard let file = files.first else {
            throw LinguaError.message("No <file> in SDLXLIFF. / 文件中没有 <file>。")
        }
        let resolver = FormattingResolver(document: document)
        if let existing = resolver.fileFormats.first?.first(where: { kind.matches($0.value) })?.key {
            return existing
        }
        // Prefer our stable id if somehow present without parse match.
        if resolver.format(forTagID: kind.preferredTagID) != nil {
            return kind.preferredTagID
        }
        try installTagDefinition(kind: kind, in: file, document: document)
        return kind.preferredTagID
    }

    private static func installTagDefinition(
        kind: InlineFormatKind,
        in file: XMLElement,
        document: XMLDocument
    ) throws {
        let header: XMLElement
        if let existing = (file.children ?? [])
            .compactMap({ $0 as? XMLElement })
            .first(where: { xmlLocalName($0) == "header" }) {
            header = existing
        } else {
            header = XMLElement(name: "header")
            if let body = (file.children ?? [])
                .compactMap({ $0 as? XMLElement })
                .first(where: { xmlLocalName($0) == "body" }) {
                file.insertChild(header, at: body.index)
            } else {
                file.addChild(header)
            }
        }

        let fmtDefs = findOrCreateContainer(
            named: "fmt-defs",
            uri: SDLNamespaces.sdl,
            in: header,
            document: document
        )
        let tagDefs = findOrCreateContainer(
            named: "tag-defs",
            uri: SDLNamespaces.sdl,
            in: header,
            document: document
        )

        if !childElements(fmtDefs, named: "fmt-def").contains(where: {
            $0.attribute(forName: "id")?.stringValue == kind.preferredFmtID
        }) {
            let fmtDef = sdlElement("fmt-def", attrs: ["id": kind.preferredFmtID])
            let value = sdlElement("value", attrs: ["key": kind.fmtKey], text: kind.fmtValue)
            fmtDef.addChild(value)
            fmtDefs.addChild(fmtDef)
        }

        if !childElements(tagDefs, named: "tag").contains(where: {
            $0.attribute(forName: "id")?.stringValue == kind.preferredTagID
        }) {
            let tag = sdlElement("tag", attrs: ["id": kind.preferredTagID])
            let bpt = sdlElement(
                "bpt",
                attrs: ["name": "cf", "word-end": "false", "can-hide": "true"],
                text: kind.cfOpen
            )
            let ept = sdlElement(
                "ept",
                attrs: ["name": "cf", "word-end": "false", "can-hide": "true"],
                text: "</cf>"
            )
            let fmtRef = sdlElement("fmt", attrs: ["id": kind.preferredFmtID])
            tag.addChild(bpt)
            tag.addChild(ept)
            tag.addChild(fmtRef)
            tagDefs.addChild(tag)
        }
    }

    private static func sdlElement(
        _ name: String,
        attrs: [String: String] = [:],
        text: String? = nil
    ) -> XMLElement {
        let el = XMLNode.element(withName: name, uri: SDLNamespaces.sdl) as! XMLElement
        for (k, v) in attrs {
            setAttribute(el, k, v)
        }
        if let text {
            el.stringValue = text
        }
        return el
    }

    private static func findOrCreateContainer(
        named name: String,
        uri: String,
        in header: XMLElement,
        document: XMLDocument
    ) -> XMLElement {
        if let existing = elementsBelow(header, includeSelf: true).first(where: {
            xmlLocalName($0) == name
        }) {
            return existing
        }
        let created = XMLNode.element(withName: name, uri: uri) as! XMLElement
        header.addChild(created)
        return created
    }

    private static func childElements(_ parent: XMLElement, named name: String) -> [XMLElement] {
        (parent.children ?? [])
            .compactMap { $0 as? XMLElement }
            .filter { xmlLocalName($0) == name }
    }

    // MARK: - Range mapping on TagPlan.text (UTF-16)

    public struct GapSlice: Equatable {
        public var gapIndex: Int
        public var start: Int  // String.Index offset in characters
        public var end: Int
    }

    /// Map a UTF-16 range in `plan.text` onto a single gap. Returns nil if empty, out of range, or crosses tags.
    public static func gapSlice(plan: TagPlan, draftUTF16Range: NSRange) -> GapSlice? {
        guard draftUTF16Range.length > 0, draftUTF16Range.location != NSNotFound else { return nil }
        let text = plan.text as NSString
        guard draftUTF16Range.location >= 0,
              NSMaxRange(draftUTF16Range) <= text.length else { return nil }

        let start16 = draftUTF16Range.location
        let end16 = NSMaxRange(draftUTF16Range)

        var cursor = 0 // utf16
        var gapIndex = 0
        var startGap: (Int, Int)? // gapIndex, char offset
        var endGap: (Int, Int)?

        func consumeGap(_ gap: String) {
            let gapNS = gap as NSString
            let gapLen = gapNS.length
            let gapStart = cursor
            let gapEnd = cursor + gapLen
            if startGap == nil, start16 >= gapStart, start16 <= gapEnd {
                let local = start16 - gapStart
                startGap = (gapIndex, (gapNS.substring(to: local) as String).count)
            }
            if endGap == nil, end16 >= gapStart, end16 <= gapEnd {
                let local = end16 - gapStart
                endGap = (gapIndex, (gapNS.substring(to: local) as String).count)
            }
            cursor = gapEnd
            gapIndex += 1
        }

        consumeGap(plan.gaps[0])
        for i in plan.tokens.indices {
            let tokenLen = (plan.tokens[i] as NSString).length
            // Selection must not start/end inside a token.
            if start16 > cursor, start16 < cursor + tokenLen { return nil }
            if end16 > cursor, end16 < cursor + tokenLen { return nil }
            cursor += tokenLen
            consumeGap(plan.gaps[i + 1])
        }

        guard let s = startGap, let e = endGap, s.0 == e.0, e.1 > s.1 else { return nil }
        return GapSlice(gapIndex: s.0, start: s.1, end: e.1)
    }


    /// When the user clicks B/I/U with no selection: wrap the whole segment if it has
    /// no tags; otherwise wrap the entire plain gap that contains the caret.
    public static func rangeForEmptyCaret(plan: TagPlan, caretDraftUTF16: Int) -> NSRange? {
        let textLen = (plan.text as NSString).length
        guard textLen > 0 else { return nil }
        if plan.tokens.isEmpty {
            return NSRange(location: 0, length: textLen)
        }
        let caret = max(0, min(caretDraftUTF16, textLen))
        var cursor = 0
        var fallback: NSRange?
        for i in plan.gaps.indices {
            let gapLen = (plan.gaps[i] as NSString).length
            let gapStart = cursor
            let gapEnd = cursor + gapLen
            if gapLen > 0 {
                let range = NSRange(location: gapStart, length: gapLen)
                if fallback == nil { fallback = range }
                // Caret inside gap, or at end of gap (before following tag / EOF).
                if caret >= gapStart && caret <= gapEnd {
                    return range
                }
            }
            cursor = gapEnd
            if i < plan.tokens.count {
                let tokLen = (plan.tokens[i] as NSString).length
                // Caret on a tag → prefer following text gap, else previous.
                if caret >= cursor && caret < cursor + tokLen {
                    if i + 1 < plan.gaps.count, (plan.gaps[i + 1] as NSString).length > 0 {
                        return NSRange(
                            location: cursor + tokLen,
                            length: (plan.gaps[i + 1] as NSString).length
                        )
                    }
                    if let fallback { return fallback }
                }
                cursor += tokLen
            }
        }
        return fallback
    }

    /// Rebuild `root` children like `TagPlan.apply`, wrapping `slice` of one gap in `<g id="tagID">`.
    public static func wrapGap(
        plan: TagPlan,
        tagID: String,
        slice: GapSlice,
        tracking: Bool,
        document: XMLDocument,
        author: String
    ) throws {
        let parts = plan.gaps
        guard slice.gapIndex >= 0, slice.gapIndex < parts.count else {
            throw LinguaError.message("Invalid selection. / 无效的选区。")
        }
        let gap = parts[slice.gapIndex]
        let chars = Array(gap)
        guard slice.start >= 0, slice.end <= chars.count, slice.start < slice.end else {
            throw LinguaError.message("Invalid selection. / 无效的选区。")
        }
        let before = String(chars[..<slice.start])
        let mid = String(chars[slice.start..<slice.end])
        let after = String(chars[slice.end...])

        let result = plan.root.copy() as! XMLElement
        result.setChildren([])
        var stack: [XMLElement] = [result]

        for i in parts.indices {
            let parent = stack.last!

            if i == slice.gapIndex {
                if tracking && parts[i] != plan.gaps[i] {
                    // Should not happen — we wrap current gaps.
                }
                if !before.isEmpty {
                    parent.addChild(XMLNode.text(withStringValue: before) as! XMLNode)
                }
                let g = XMLElement(name: "g")
                setAttribute(g, "id", tagID)
                g.addChild(XMLNode.text(withStringValue: mid) as! XMLNode)
                parent.addChild(g)
                if !after.isEmpty {
                    parent.addChild(XMLNode.text(withStringValue: after) as! XMLNode)
                }
            } else if !parts[i].isEmpty {
                parent.addChild(XMLNode.text(withStringValue: parts[i]) as! XMLNode)
            }

            guard i < plan.actions.count else { continue }
            switch plan.actions[i] {
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
        plan.root.setChildren(children)
        _ = tracking
        _ = author
        _ = document
    }

    /// If the selection is exactly the full text of a single `<g id=tagID>`, unwrap it (toggle off).
    public static func unwrapIfExactMatch(
        plan: TagPlan,
        tagID: String,
        slice: GapSlice
    ) -> Bool {
        // Look for pattern: gap empty before open(g id), mid gap is selection spanning whole that gap between open/close, after empty
        // Simpler: if slice covers entire gap i, and actions[i-1] is open g with tagID and actions[i] is close... 
        // gaps: g0, [open], g1, [close], g2
        // Selecting all of g1 with surrounding open/close of our tag → unwrap
        let openIndex = slice.gapIndex - 1
        guard openIndex >= 0, openIndex < plan.actions.count,
              slice.gapIndex < plan.gaps.count,
              slice.start == 0,
              slice.end == plan.gaps[slice.gapIndex].count,
              case .open(let el) = plan.actions[openIndex],
              xmlLocalName(el) == "g",
              el.attribute(forName: "id")?.stringValue == tagID,
              openIndex + 1 < plan.actions.count,
              case .close = plan.actions[openIndex + 1]
        else { return false }

        // Rebuild without that open/close, merging gaps.
        let result = plan.root.copy() as! XMLElement
        result.setChildren([])
        var stack: [XMLElement] = [result]
        var skipClose = false

        for i in plan.gaps.indices {
            let parent = stack.last!
            if !plan.gaps[i].isEmpty {
                parent.addChild(XMLNode.text(withStringValue: plan.gaps[i]) as! XMLNode)
            }
            guard i < plan.actions.count else { continue }
            if i == openIndex, case .open = plan.actions[i] {
                skipClose = true
                continue // skip open — content stays in parent
            }
            if skipClose, case .close = plan.actions[i] {
                skipClose = false
                continue
            }
            switch plan.actions[i] {
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
        plan.root.setChildren(children)
        return true
    }
}
