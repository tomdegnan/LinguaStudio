import Foundation

/// In-memory SDLXLIFF document with surgical DOM edits and stable segment keys.
public final class SDLXLIFFDocument {

    public private(set) var xmlDocument: XMLDocument
    public private(set) var rows: [SegmentRow] = []

    /// Live DOM pointers keyed by stable SegmentKey.
    public private(set) var sourceNodes: [SegmentKey: XMLElement] = [:]
    public private(set) var targetNodes: [SegmentKey: XMLElement] = [:]
    public private(set) var segDefNodes: [SegmentKey: XMLElement] = [:]
    public private(set) var tagPlans: [SegmentKey: TagPlan] = [:]

    /// Keys whose lock flag changed this session (written on save).
    public private(set) var lockChanges: Set<SegmentKey> = []

    public var authorName: String

    public init(data: Data, authorName: String = "Lingua Studio") throws {
        self.authorName = authorName
        self.xmlDocument = try WhitespacePreservingParser.parse(data)
        try rebuildIndex()
    }

    // MARK: - Load / index

    private func rebuildIndex() throws {
        guard let root = xmlDocument.rootElement() else {
            throw LinguaError.message("XML has no root element. / XML 没有根节点。")
        }

        var items: [SegmentRow] = []
        sourceNodes = [:]
        targetNodes = [:]
        segDefNodes = [:]
        tagPlans = [:]

        let units = elementsBelow(root).filter { xmlLocalName($0) == "trans-unit" }

        for unit in units {
            let unitId = unit.attribute(forName: "id")?.stringValue ?? ""
            let translateNo =
                unit.attribute(forName: "translate")?.stringValue?.lowercased() == "no"

            let children = (unit.children ?? []).compactMap { $0 as? XMLElement }
            guard
                let segSource = children.first(where: { xmlLocalName($0) == "seg-source" }),
                let target = children.first(where: { xmlLocalName($0) == "target" })
            else {
                continue
            }

            let sourceMarks = elementsBelow(segSource).filter {
                xmlLocalName($0) == "mrk"
                    && $0.attribute(forName: "mtype")?.stringValue == "seg"
            }
            let targetMarks = elementsBelow(target).filter {
                xmlLocalName($0) == "mrk"
                    && $0.attribute(forName: "mtype")?.stringValue == "seg"
            }

            let definitions = children.first { xmlLocalName($0) == "seg-defs" }

            for sourceMark in sourceMarks {
                guard let mid = sourceMark.attribute(forName: "mid")?.stringValue else {
                    continue
                }
                guard let targetMark = targetMarks.first(where: {
                    $0.attribute(forName: "mid")?.stringValue == mid
                }) else {
                    continue
                }

                let key = SegmentKey(unitId: unitId, mid: mid)
                var locked = false
                var status: SegmentStatus = .original

                if let defs = definitions,
                   let segStatus = elementsBelow(defs).first(where: {
                       xmlLocalName($0) == "seg"
                           && $0.attribute(forName: "id")?.stringValue == mid
                   }) {
                    segDefNodes[key] = segStatus
                    if segStatus.attribute(forName: "locked")?.stringValue?.lowercased() == "true" {
                        locked = true
                    }
                    let conf = segStatus.attribute(forName: "conf")?.stringValue ?? ""
                    if conf == "Translated" {
                        status = .confirmed
                    } else if conf == "Draft" {
                        status = .draft
                    }
                }

                let pending = RevisionFactory.hasPending(in: targetMark)
                let row = SegmentRow(
                    id: key,
                    source: visibleText(sourceMark),
                    target: visibleText(targetMark),
                    status: status,
                    isLocked: locked,
                    isUntranslatable: translateNo,
                    hasPendingRevisions: pending
                )
                items.append(row)
                sourceNodes[key] = sourceMark
                targetNodes[key] = targetMark
                tagPlans[key] = TagPlan(targetMark)
            }
        }

        guard !items.isEmpty else {
            throw LinguaError.message(
                "No recognizable bilingual segments found. / 没有找到可识别的双语句段。"
            )
        }
        rows = items
    }

    /// Reload from serialized bytes (used by history restore). Preserves author.
    public func reload(from data: Data) throws {
        xmlDocument = try WhitespacePreservingParser.parse(data)
        lockChanges = []
        try rebuildIndex()
    }

    // MARK: - Editing

    public func plan(for key: SegmentKey) -> TagPlan? {
        tagPlans[key]
    }

    /// Draft for opening the inline editor, always derived from the live target node
    /// the row display renders (rebuilds the cached plan if it ever drifted from it).
    /// Returns nil when there is no plan — callers must not fall back to `row.target`,
    /// which has no tag tokens and would strip tags/revisions on flush.
    public func editorDraft(for key: SegmentKey) -> String? {
        guard let node = targetNodes[key] else { return tagPlans[key]?.text }
        let fresh = TagPlan(node)
        if let cached = tagPlans[key], cached.root === node, cached.text == fresh.text {
            return cached.text
        }
        tagPlans[key] = fresh
        if let i = rows.firstIndex(where: { $0.id == key }) {
            rows[i].target = visibleText(node)
        }
        return fresh.text
    }

    public func applyEdit(
        key: SegmentKey,
        draft: String,
        tracking: Bool
    ) throws {
        guard let plan = tagPlans[key], let rowIndex = rows.firstIndex(where: { $0.id == key }) else {
            throw LinguaError.message("Unknown segment. / 未知句段。")
        }
        guard rows[rowIndex].isEditable else {
            throw LinguaError.message("Segment is locked or not translatable. / 句段已锁定或不可翻译。")
        }

        if draft == plan.text {
            return
        }

        try plan.apply(draft, tracking: tracking, document: xmlDocument, author: authorName)
        tagPlans[key] = TagPlan(plan.root)
        rows[rowIndex].target = visibleText(plan.root)
        rows[rowIndex].status = .draft
        rows[rowIndex].hasPendingRevisions = RevisionFactory.hasPending(in: plan.root)
    }

    public func resolveRevisions(key: SegmentKey, accept: Bool) throws {
        guard let target = targetNodes[key],
              let rowIndex = rows.firstIndex(where: { $0.id == key }) else {
            throw LinguaError.message("Unknown segment. / 未知句段。")
        }
        guard rows[rowIndex].isEditable else {
            throw LinguaError.message("Segment is locked or not translatable. / 句段已锁定或不可翻译。")
        }

        try RevisionFactory.resolve(target, accept: accept)
        tagPlans[key] = TagPlan(target)
        rows[rowIndex].target = visibleText(target)
        rows[rowIndex].status = .draft
        rows[rowIndex].hasPendingRevisions = RevisionFactory.hasPending(in: target)
    }

    public func confirm(key: SegmentKey) {
        guard let rowIndex = rows.firstIndex(where: { $0.id == key }) else { return }
        guard rows[rowIndex].isEditable, !rows[rowIndex].target.isEmpty else { return }
        rows[rowIndex].status = .confirmed
    }

    public func toggleLock(key: SegmentKey) throws {
        guard segDefNodes[key] != nil else {
            throw LinguaError.message(
                "This segment has no writable Trados seg-defs entry. / 此句段没有可写入的 Trados 状态信息，无法切换锁定。"
            )
        }
        guard let rowIndex = rows.firstIndex(where: { $0.id == key }) else { return }
        rows[rowIndex].isLocked.toggle()
        lockChanges.insert(key)
    }

    /// Wrap (or unwrap) a UTF-16 range of the segment's TagPlan draft with bold/italic/underline.
    /// Selection must lie in a single text gap (not across tags). Updates the live DOM + plan.
    @discardableResult
    public func applyInlineFormat(
        key: SegmentKey,
        kind: InlineFormatKind,
        draftUTF16Range: NSRange
    ) throws -> String {
        guard let plan = tagPlans[key], let rowIndex = rows.firstIndex(where: { $0.id == key }) else {
            throw LinguaError.message("Unknown segment. / 未知句段。")
        }
        guard rows[rowIndex].isEditable else {
            throw LinguaError.message("Segment is locked or not translatable. / 句段已锁定或不可翻译。")
        }
        guard let slice = FormatTagSupport.gapSlice(plan: plan, draftUTF16Range: draftUTF16Range) else {
            throw LinguaError.message(
                "请在同一段纯文本内选中文字（不要跨标签）。 / Select text within one plain run (not across tags)."
            )
        }
        let tagID = try FormatTagSupport.ensureTagID(for: kind, in: xmlDocument)
        if FormatTagSupport.unwrapIfExactMatch(plan: plan, tagID: tagID, slice: slice) {
            // unwrapped
        } else {
            try FormatTagSupport.wrapGap(
                plan: plan,
                tagID: tagID,
                slice: slice,
                tracking: false,
                document: xmlDocument,
                author: authorName
            )
        }
        tagPlans[key] = TagPlan(plan.root)
        rows[rowIndex].target = visibleText(plan.root)
        rows[rowIndex].status = .draft
        rows[rowIndex].hasPendingRevisions = RevisionFactory.hasPending(in: plan.root)
        return tagPlans[key]!.text
    }

    public func setStatus(_ status: SegmentStatus, for key: SegmentKey) {
        guard let rowIndex = rows.firstIndex(where: { $0.id == key }) else { return }
        rows[rowIndex].status = status
    }

    // MARK: - Serialize

    /// Sync lock/conf attributes into the live DOM, then serialize.
    public func serializedData() throws -> Data {
        for key in lockChanges {
            guard let statusNode = segDefNodes[key],
                  let row = rows.first(where: { $0.id == key }) else { continue }
            setAttribute(statusNode, "locked", row.isLocked ? "true" : "false")
        }

        for row in rows where row.status == .draft || row.status == .confirmed {
            guard let statusNode = segDefNodes[row.id],
                  let conf = row.status.sdlConf else { continue }
            setAttribute(statusNode, "conf", conf)
        }

        return xmlDocument.xmlData(options: [.nodePreserveAll])
    }

    /// Atomic write to disk.
    public func write(to url: URL) throws {
        let data = try serializedData()
        try data.write(to: url, options: [.atomic])
        lockChanges = []
    }

    // MARK: - Snapshot helpers for history

    public func makeSnapshot(selection: SegmentKey?) throws -> EditSnapshot {
        let data = try serializedData()
        var statuses: [String: String] = [:]
        var targets: [String: String] = [:]
        for row in rows {
            statuses[row.id.description] = row.status.rawValue
            targets[row.id.description] = row.target
        }
        return EditSnapshot(
            data: data,
            selectionKey: selection,
            statuses: statuses,
            targets: targets
        )
    }

    public func restore(snapshot: EditSnapshot) throws {
        try reload(from: snapshot.data)
        for i in rows.indices {
            let keyDesc = rows[i].id.description
            if let raw = snapshot.statuses[keyDesc],
               let status = SegmentStatus(rawValue: raw) {
                rows[i].status = status
            }
        }
    }

    // MARK: - Tag-safe replace / bulk review

    /// Replace `find` with `replacement` in one segment target's plain-text gaps only.
    /// Returns the GapReplaceResult; on `.applied` the live DOM and row are updated.
    @discardableResult
    public func replaceInTarget(
        key: SegmentKey,
        find: String,
        replacement: String,
        options: SearchOptions,
        tracking: Bool,
        firstOnly: Bool = false,
        startFromDraftUTF16: Int = 0
    ) throws -> GapReplaceResult {
        guard let plan = tagPlans[key],
              let rowIndex = rows.firstIndex(where: { $0.id == key }) else {
            throw LinguaError.message("Unknown segment. / 未知句段。")
        }
        guard rows[rowIndex].isEditable else {
            throw LinguaError.message("Segment is locked or not translatable. / 句段已锁定或不可翻译。")
        }
        // Pending revisions: editable when Track Changes is ON (in-place revision gaps).
        // When OFF, replaceInGaps leaves revision gaps locked (skippedLocked / partial).
        let result = SearchReplace.replaceInGaps(
            plan: plan,
            find: find,
            replacement: replacement,
            options: options,
            firstOnly: firstOnly,
            startFromDraftUTF16: startFromDraftUTF16,
            allowRevisionEdits: tracking
        )
        guard case .applied(let draft, _, _) = result else {
            return result
        }
        try applyEdit(key: key, draft: draft, tracking: tracking)
        return result
    }

    /// Accept or reject pending revisions for every key in `keys`.
    /// Returns how many segments were resolved.
    @discardableResult
    public func resolveRevisions(keys: [SegmentKey], accept: Bool) throws -> Int {
        var count = 0
        for key in keys {
            guard let row = rows.first(where: { $0.id == key }),
                  row.hasPendingRevisions,
                  row.isEditable else { continue }
            try resolveRevisions(key: key, accept: accept)
            count += 1
        }
        return count
    }
}
