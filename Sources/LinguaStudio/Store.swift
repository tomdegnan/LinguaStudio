import SwiftUI
import AppKit
import UniformTypeIdentifiers
#if canImport(LinguaCore)
import LinguaCore
#endif

/// App session state: document, selection, filters, review mode, search/replace, history.
@MainActor
final class Store: ObservableObject {

    @Published var document: SDLXLIFFDocument?
    @Published var rows: [SegmentRow] = []
    @Published var selected: SegmentKey?
    @Published var editingID: SegmentKey?
    @Published var draft: String = ""
    /// After Replace: editor selects this draft UTF-16 range once (no find advance).
    @Published var pendingDraftSelection: NSRange? = nil
    @Published var showTags = true
    /// Full `‹id›` chips vs compact arrow pair (only when showTags).
    @Published var tagStyle: TagDisplayStyle = .full
    @Published var showInvisibles = false
    @Published var tracking = false
    @Published var dirty = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?
    @Published var fileURL: URL?
    @Published var showHistory = true
    @Published var showSettings = false
    @Published var showReplaceSheet = false
    @Published var historyEntries: [HistoryEntry] = []
    @Published var historyPosition = 0

    // Search / filter
    @Published var sourceQuery = ""
    @Published var targetQuery = ""
    /// Replace-panel Find text — independent of the table filter (`targetQuery`).
    @Published var findText = ""
    @Published var replaceWith = ""
    @Published var useRegex = false
    @Published var caseSensitive = false
    @Published var wholeWord = false
    @Published var statusFilter = "all"
    /// Segments kept in the filtered list after an action that would otherwise hide them
    /// (e.g. confirm under 「草稿」). Cleared by 「刷新」 or changing the status filter.
    @Published private(set) var filterHeldKeys: Set<SegmentKey> = []

    // Review / 核对 mode (Studio-like)
    @Published var reviewMode = false

    /// Display-only formatting (bold/italic/…) resolved from tag-defs + fmt-defs.
    /// Never written back to the document.
    @Published var formatting: FormattingResolver = .empty

    private let history = HistoryManager(maxDepth: 100)

    /// Bumped every time an inline editor is (re)opened; forces the editor to rebuild
    /// from `draft` so a reused/stale NSTextView can never show old text.
    @Published private(set) var editSession = 0

    init() {
        let s = AppSettings.shared
        showTags = s.showTags
        tagStyle = s.tagStyle
        showInvisibles = s.showInvisibles
        showHistory = s.showHistoryPanel
        tracking = s.trackingDefault
        history.maxDepth = s.maxHistorySteps
    }

    /// Apply persisted defaults into the live session (Settings → Reset / Apply).
    func applySettingsDefaults(from s: AppSettings) {
        showTags = s.showTags
        tagStyle = s.tagStyle
        showInvisibles = s.showInvisibles
        showHistory = s.showHistoryPanel
        // Don't force tracking mid-document; only depth + display prefs.
        history.maxDepth = s.maxHistorySteps
        syncHistoryUI()
        // Force editor rebuild with new typography.
        if editingID != nil {
            editSession &+= 1
        }
    }

    func applyHistoryDepth(_ depth: Int) {
        history.maxDepth = depth
        syncHistoryUI()
    }

    /// The live inline editor, registered by RichSegmentEditor. flushEditing reads
    /// only from an editor whose `segmentKey` matches `editingID`.
    weak var activeEditor: SegmentTextView?

    /// Editor currently showing `key`, if any (never another row's editor).
    func liveEditor(for key: SegmentKey) -> SegmentTextView? {
        if let editor = activeEditor, editor.segmentKey == key, editor.window != nil {
            return editor
        }
        if let editor = NSApp.keyWindow?.firstResponder as? SegmentTextView,
           editor.segmentKey == key {
            return editor
        }
        return nil
    }

    /// Open the inline editor for `id` with a draft taken from the live target node.
    /// Never falls back to `row.target` (plain text without tag tokens).
    /// Baseline draft when the editor opened; used to detect first real edit → blue.
    private var editBaseline: String = ""

    private func startEditing(_ id: SegmentKey) {
        guard let document else {
            editingID = nil
            draft = ""
            editBaseline = ""
            return
        }
        // Prefer live editor draft; if missing/empty but the plan still has text,
        // never open the shared editor on "" (select/filter remount race).
        let planText = document.plan(for: id)?.text ?? ""
        let loaded = document.editorDraft(for: id)
        let text: String
        if let loaded, !loaded.isEmpty {
            text = loaded
        } else if !planText.isEmpty {
            text = planText
        } else if let loaded {
            text = loaded
        } else {
            editingID = nil
            draft = ""
            editBaseline = ""
            return
        }
        if rows != document.rows { rows = document.rows }
        draft = text
        editBaseline = text
        editSession += 1
        editingID = id
    }

    /// Called on every editor onChange. Turns the status dot blue only when content
    /// actually differs from the text loaded at startEditing (not on mere select).
    func noteEditorChange(_ value: String) {
        guard let id = editingID else { return }
        // Shared-editor remount can push "" once; do not clobber a good draft/baseline.
        if value.isEmpty, !draft.isEmpty, !editBaseline.isEmpty {
            return
        }
        draft = value
        guard value != editBaseline else { return }
        if let idx = rows.firstIndex(where: { $0.id == id }), rows[idx].status != .draft {
            rows[idx].status = .draft
        }
    }

    private var sdlType: UTType {
        UTType(filenameExtension: "sdlxliff") ?? .xml
    }

    var searchOptions: SearchOptions {
        SearchOptions(
            caseSensitive: caseSensitive,
            wholeWord: wholeWord,
            useRegex: useRegex
        )
    }

    // MARK: - Derived

    var selectedIndex: Int? {
        guard let selected else { return nil }
        return rows.firstIndex { $0.id == selected }
    }

    /// Rows visible in the table (status + text filters; Review mode prefers pending).
    /// `filterHeldKeys` keeps just-acted-on rows visible until manual refresh.
    var filteredRows: [SegmentRow] {
        rows.filter { row in
            let textOK = SearchReplace.textMatches(row.source, query: sourceQuery, options: searchOptions)
                && SearchReplace.textMatches(row.target, query: targetQuery, options: searchOptions)
            guard textOK else { return false }
            if statusMatches(row) { return true }
            return filterHeldKeys.contains(row.id)
        }
    }

    var filterHasHeldRows: Bool { !filterHeldKeys.isEmpty }

    /// Re-apply status filter strictly — drop rows held after confirm/lock/etc.
    func refreshFilter() {
        filterHeldKeys.removeAll()
    }

    /// Change status filter and clear any held rows (intentional filter change).
    func applyStatusFilter(_ key: String) {
        guard key != statusFilter else { return }
        statusFilter = key
        filterHeldKeys.removeAll()
    }

    /// Keep `id` visible under the current status filter after an action that changes status/flags.
    private func holdInFilterIfNeeded(_ id: SegmentKey) {
        let restrictive: Bool = {
            switch statusFilter {
            case "all", "全部": return false
            default: return true
            }
        }()
        guard restrictive else { return }
        // Only hold if the row no longer matches (or is about to stop matching).
        filterHeldKeys.insert(id)
    }

    /// Pending-revision keys in document order, optionally limited to current filter set
    /// when status/text filters are active; in Review mode always among filteredRows.
    var pendingKeysInScope: [SegmentKey] {
        let scope = reviewMode ? filteredRows : rows
        return RevisionFactory.pendingKeys(in: scope)
    }

    var matchCount: Int { filteredRows.count }

    /// 1-based index of selection within filtered results, or 0 if none selected in set.
    var matchIndex: Int {
        guard let selected,
              let idx = filteredRows.firstIndex(where: { $0.id == selected }) else {
            return 0
        }
        return idx + 1
    }

    static let statusFilterKeys = ["all", "untranslated", "draft", "confirmed", "revisions", "locked"]

    static func statusFilterLabel(_ key: String) -> String {
        switch key {
        case "all": return L10n.t("status.all")
        case "untranslated": return L10n.t("status.untranslated")
        case "draft": return L10n.t("status.draft")
        case "confirmed": return L10n.t("status.confirmed")
        case "revisions": return L10n.t("status.revisions")
        case "locked": return L10n.t("status.locked")
        default: return key
        }
    }

    private func statusMatches(_ row: SegmentRow) -> Bool {
        switch statusFilter {
        case "all", "全部":
            return true
        case "revisions", "有修订": return row.hasPendingRevisions
        case "untranslated", "未翻译": return row.target.isEmpty || row.status == .untranslated
        case "draft", "草稿": return row.status == .draft
        case "confirmed", "已确认": return row.status == .confirmed
        case "locked", "已锁定": return row.isLocked
        default: return row.status.rawValue == statusFilter
        }
    }

    var regexInvalid: Bool {
        guard useRegex else { return false }
        let opts = searchOptions
        return [sourceQuery, targetQuery, findText].contains {
            !$0.isEmpty && SearchReplace.matchRanges(in: "x", pattern: $0, options: opts) == nil
        }
    }

    /// Invalid regex specifically for the Replace Find field.
    var replaceRegexInvalid: Bool {
        guard useRegex, !findText.isEmpty else { return false }
        return SearchReplace.matchRanges(in: "x", pattern: findText, options: searchOptions) == nil
    }

    /// Segments whose target matches Replace Find — document order, ignores table filters.
    var replaceHitRows: [SegmentRow] {
        guard !findText.isEmpty, !replaceRegexInvalid else { return [] }
        return rows.filter {
            SearchReplace.textMatches($0.target, query: findText, options: searchOptions)
        }
    }

    var replaceMatchCount: Int { replaceHitRows.count }

    /// 1-based index of selection within replace hits, or 0 if none.
    var replaceMatchIndex: Int {
        guard let selected,
              let idx = replaceHitRows.firstIndex(where: { $0.id == selected }) else {
            return 0
        }
        return idx + 1
    }

    var selectedHasPending: Bool {
        guard let selected else { return false }
        return rows.first(where: { $0.id == selected })?.hasPendingRevisions == true
    }

    // MARK: - Open / Save

    func open() {
        if dirty {
            let alert = NSAlert()
            alert.messageText = L10n.t("msg.unsavedTitle")
            alert.informativeText = L10n.t("msg.unsavedBody")
            alert.addButton(withTitle: L10n.t("alert.cancel"))
            alert.addButton(withTitle: L10n.t("msg.discardOpen"))
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [sdlType, .xml]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let author = NSFullUserName().isEmpty ? NSUserName() : NSFullUserName()
            let doc = try SDLXLIFFDocument(data: data, authorName: author)
            document = doc
            rows = doc.rows
            formatting = FormattingResolver(document: doc.xmlDocument)
            fileURL = url
            dirty = false
            selected = nil
            editingID = nil
            draft = ""
            tracking = false
            reviewMode = false
            history.clear()
            syncHistoryUI()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() {
        guard flushEditing() else { return }
        if let url = fileURL {
            write(to: url)
        } else {
            saveAs()
        }
    }

    func saveAs() {
        guard flushEditing() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "translation.sdlxliff"
        panel.allowedContentTypes = [sdlType]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(to: url)
        fileURL = url
    }

    private func write(to url: URL) {
        guard let document else {
            errorMessage = L10n.t("msg.noDocument")
            return
        }
        do {
            try document.write(to: url)
            dirty = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Selection / editing

    @discardableResult
    func flushEditing() -> Bool {
        guard let id = editingID, let document else {
            return true
        }
        // CRITICAL: pull the live editor contents *before* clearing editingID or
        // resigning first responder. macOS IME (Chinese etc.) keeps uncommitted
        // marked text only in the NSTextView; resigning commits it via textDidChange
        // after editingID is already nil, and onChange then drops the update —
        // that was dropping just-typed CJK on ⌘↩ / row switch.
        //
        // Also: a reused/stale editor can briefly show stripped text (lost `[]` or
        // CJK) while `draft` still holds the last good onChange value. FlushPolicy
        // picks the longest TagPlan-valid candidate so we never write the stripped
        // snapshot over good content when switching rows (记录修订 OFF or ON).
        let editorSnapshot = liveEditor(for: id)?.committedInternalDraft()
        let planText = document.plan(for: id)?.text ?? draft
        var chosen = FlushPolicy.draftToCommit(
            FlushPolicy.Candidates(editor: editorSnapshot, store: draft, plan: planText),
            split: { try document.plan(for: id)?.split($0) ?? [$0] }
        )
        // Never write an empty draft over a non-empty target on leave/select.
        if chosen.isEmpty, !planText.isEmpty {
            chosen = planText
        }
        draft = chosen
        do {
            // Always snapshot before apply — never skip history when content changes.
            let before = try document.makeSnapshot(selection: selected)
            try document.applyEdit(key: id, draft: chosen, tracking: tracking)
            rows = document.rows
            let after = try document.makeSnapshot(selection: selected)
            if HistoryManager.shouldRecord(before: before, after: after) {
                dirty = true
                history.record(before: before, after: after, title: L10n.tf("hist.edit", id.mid))
                syncHistoryUI()
            }
            editingID = nil
            editBaseline = ""
            // Keep `draft` as the committed text until startEditing replaces it —
            // clearing to "" here let a one-frame SwiftUI refresh open the next
            // row's editor with an empty draft and then flush that empty string.
            NSApp.keyWindow?.makeFirstResponder(nil)
            return true
        } catch {
            // Never trap the grid on flush — discard illegal draft and leave the segment.
            let msg = error.localizedDescription
            if msg.contains("记录修订") || msg.contains("Track Changes") || msg.contains("pending revisions") {
                draft = planText
                errorMessage = nil
                editingID = nil
                editBaseline = ""
                NSApp.keyWindow?.makeFirstResponder(nil)
                return true
            }
            errorMessage = msg
            return false
        }
    }

    func beginEditing(_ id: SegmentKey) {
        guard let row = rows.first(where: { $0.id == id }), row.isEditable else { return }
        if reviewMode {
            // Studio-like: Review mode is for accept/reject, not free editing.
            let alert = NSAlert()
            alert.messageText = L10n.t("msg.reviewEditTitle")
            alert.informativeText = L10n.t("msg.reviewEditBody")
            alert.addButton(withTitle: L10n.t("msg.leaveReviewEdit"))
            alert.addButton(withTitle: L10n.t("alert.cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            reviewMode = false
        }
        startEditing(id)
    }

    /// Select a segment. Flushes the shared editor first (full TagPlan commit),
    /// then moves the single live editor into the new row (Trados-like grid).
    func choose(_ id: SegmentKey?) {
        // Never leave a modal error trapping the grid (e.g. old revision-lock throw).
        if let msg = errorMessage, msg.contains("记录修订") || msg.contains("Track Changes") {
            errorMessage = nil
        }
        // Idempotent: row + target both attach tap handlers; a single click must
        // not flush-and-reopen the segment we just activated.
        if id == selected {
            if id != editingID {
                openInlineEditorIfNeeded(for: id)
            }
            return
        }
        let transition = SingleEditorPolicy.choose(
            current: editingID,
            next: id,
            flush: { flushEditing() }
        )
        guard transition.flushed else { return }
        selected = transition.active
        openInlineEditorIfNeeded(for: transition.active)
    }

    /// After selection settles, put an editable segment into inline edit mode.
    /// Review mode / locked / untranslatable stay selection-only (read-only).
    private func openInlineEditorIfNeeded(for id: SegmentKey?) {
        guard let id,
              !reviewMode,
              rows.first(where: { $0.id == id })?.isEditable == true else {
            editingID = nil
            draft = ""
            NSApp.keyWindow?.makeFirstResponder(nil)
            return
        }
        startEditing(id)
    }

    /// Move selection to the previous/next row in `filteredRows` (⌥↑ / ⌥↓).
    /// Flushes draft via `choose`. Wraps at ends.
    func selectAdjacentFiltered(next: Bool) {
        let list = filteredRows
        guard !list.isEmpty else { return }
        if let selected,
           let idx = list.firstIndex(where: { $0.id == selected }) {
            if next {
                let i = list.index(after: idx)
                choose(list[i < list.endIndex ? i : list.startIndex].id)
            } else if idx == list.startIndex {
                choose(list[list.index(before: list.endIndex)].id)
            } else {
                choose(list[list.index(before: idx)].id)
            }
        } else {
            choose(next ? list[0].id : list[list.index(before: list.endIndex)].id)
        }
    }

    func cancelEdit() {
        // Drop in-progress IME composition without committing it into draft/DOM.
        if let id = editingID, let editor = liveEditor(for: id), editor.hasMarkedText() {
            editor.inputContext?.discardMarkedText()
        }
        let cancelled = editingID
        editingID = nil
        draft = ""
        editBaseline = ""
        // Revert UI-only blue if nothing was flushed to the document.
        if let cancelled, let document,
           let docRow = document.rows.first(where: { $0.id == cancelled }),
           let idx = rows.firstIndex(where: { $0.id == cancelled }) {
            rows[idx] = docRow
        }
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    func setTracking(_ on: Bool) {
        guard flushEditing() else { return }
        tracking = on
    }

    func setReviewMode(_ on: Bool) {
        guard flushEditing() else { return }
        if on {
            editingID = nil
            NSApp.keyWindow?.makeFirstResponder(nil)
            // Prefer showing pending when entering review with no status filter.
            if (statusFilter == "all" || statusFilter == "全部"), rows.contains(where: \.hasPendingRevisions) {
                statusFilter = "revisions"
            }
            // Jump to first pending in scope if nothing selected / selection not pending.
            if let first = pendingKeysInScope.first {
                if selected == nil || !(rows.first(where: { $0.id == selected })?.hasPendingRevisions ?? false) {
                    selected = first
                }
            }
        } else if statusFilter == "revisions" || statusFilter == "有修订" {
            statusFilter = "all"
        }
        reviewMode = on
        // Leaving Review: reopen inline editor for the current selection.
        if !on {
            openInlineEditorIfNeeded(for: selected)
        }
    }

    func toggleReviewMode() {
        setReviewMode(!reviewMode)
    }

    // MARK: - Confirm / lock / revisions

    func confirmAndNext() {
        guard flushEditing() else { return }
        guard let document, let id = selected,
              let index = rows.firstIndex(where: { $0.id == id }) else { return }
        guard rows[index].isEditable, !rows[index].target.isEmpty else { return }
        // Capture the visible order before confirming (status filter may hide this row after).
        let visible = filteredRows.map(\.id)

        let before = try? document.makeSnapshot(selection: selected)
        document.confirm(key: id)
        rows = document.rows
        dirty = true
        holdInFilterIfNeeded(id)
        if let before, let after = try? document.makeSnapshot(selection: selected) {
            history.record(before: before, after: after, title: L10n.tf("hist.confirm", id.mid))
            syncHistoryUI()
        }
        // Studio-like ⌘↩: optionally move to the next segment (Settings → confirm advances).
        guard AppSettings.shared.confirmAdvancesToNext else { return }
        if let pos = visible.firstIndex(of: id), pos + 1 < visible.count {
            choose(visible[pos + 1])
        } else if visible.firstIndex(of: id) == nil, index + 1 < rows.count {
            choose(rows[index + 1].id)
        }
    }

    func toggleLock() {
        guard let document, let id = selected else { return }
        guard flushEditing() else { return }
        let before = try? document.makeSnapshot(selection: selected)
        do {
            try document.toggleLock(key: id)
            rows = document.rows
            dirty = true
            holdInFilterIfNeeded(id)
            if rows.first(where: { $0.id == id })?.isLocked == true {
                editingID = nil
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
            if let before, let after = try? document.makeSnapshot(selection: selected) {
                let locked = rows.first(where: { $0.id == id })?.isLocked == true
                history.record(
                    before: before,
                    after: after,
                    title: L10n.tf(locked ? "hist.lock" : "hist.unlock", id.mid)
                )
                syncHistoryUI()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func review(accept: Bool) {
        guard let document, let id = selected else { return }
        guard flushEditing() else { return }
        let before = try? document.makeSnapshot(selection: selected)
        do {
            try document.resolveRevisions(key: id, accept: accept)
            rows = document.rows
            editingID = nil
            dirty = true
            holdInFilterIfNeeded(id)
            if let before, let after = try? document.makeSnapshot(selection: selected) {
                history.record(
                    before: before,
                    after: after,
                    title: L10n.tf(accept ? "hist.accept" : "hist.reject", id.mid)
                )
                syncHistoryUI()
            }
            // In Review mode, advance to next pending after resolve.
            if reviewMode {
                goToPending(next: true)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reviewAll(accept: Bool) {
        guard let document else { return }
        guard flushEditing() else { return }
        let keys = pendingKeysInScope
        guard !keys.isEmpty else {
            infoMessage = L10n.t("msg.noPending")
            return
        }

        let alert = NSAlert()
        alert.messageText = L10n.t(accept ? "msg.acceptAllTitle" : "msg.rejectAllTitle")
        alert.informativeText = L10n.tf(accept ? "msg.acceptAllBody" : "msg.rejectAllBody", keys.count)
        alert.addButton(withTitle: L10n.t(accept ? "msg.acceptAllBtn" : "msg.rejectAllBtn"))
        alert.addButton(withTitle: L10n.t("alert.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let before = try? document.makeSnapshot(selection: selected)
        do {
            let count = try document.resolveRevisions(keys: keys, accept: accept)
            rows = document.rows
            editingID = nil
            dirty = true
            if let before, let after = try? document.makeSnapshot(selection: selected) {
                history.record(
                    before: before,
                    after: after,
                    title: L10n.tf(accept ? "hist.acceptAll" : "hist.rejectAll", count)
                )
                syncHistoryUI()
            }
            infoMessage = L10n.tf(accept ? "msg.acceptedCount" : "msg.rejectedCount", count)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func goToPending(next: Bool) {
        guard flushEditing() else { return }
        let keys = pendingKeysInScope
        let key = next
            ? RevisionFactory.nextPending(after: selected, in: keys)
            : RevisionFactory.previousPending(before: selected, in: keys)
        if let key {
            choose(key)
        } else {
            infoMessage = L10n.t("msg.noPending")
        }
    }

    // MARK: - Find / Replace

    /// Open the floating Replace panel. Seeds Find from the table target filter when empty.
    func openReplacePanel() {
        if findText.isEmpty, !targetQuery.isEmpty {
            findText = targetQuery
        }
        showReplaceSheet = true
    }

    /// Find Next among table-filtered rows (Find bar / ⌘G). Does not drive Replace.
    func findNext() {
        guard flushEditing() else { return }
        let list = filteredRows
        guard !list.isEmpty else {
            infoMessage = L10n.t("msg.noMatches")
            return
        }
        if let selected,
           let idx = list.firstIndex(where: { $0.id == selected }) {
            let next = list.index(after: idx)
            choose(list[next < list.endIndex ? next : list.startIndex].id)
        } else {
            choose(list[0].id)
        }
    }

    /// Find Previous among table-filtered rows (Find bar / ⌘⇧G).
    func findPrevious() {
        guard flushEditing() else { return }
        let list = filteredRows
        guard !list.isEmpty else {
            infoMessage = L10n.t("msg.noMatches")
            return
        }
        if let selected,
           let idx = list.firstIndex(where: { $0.id == selected }) {
            if idx == list.startIndex {
                choose(list[list.index(before: list.endIndex)].id)
            } else {
                choose(list[list.index(before: idx)].id)
            }
        } else {
            choose(list[list.index(before: list.endIndex)].id)
        }
    }

    /// Next Find match: highlight in-editor (same segment next hit, else next segment).
    func findReplaceNext() {
        advanceReplaceHighlight(forward: true)
    }

    /// Previous Find match: highlight in-editor.
    func findReplacePrevious() {
        advanceReplaceHighlight(forward: false)
    }

    /// Move to the next/previous Find match and select it in the target editor.
    private func advanceReplaceHighlight(forward: Bool) {
        let find = findText
        guard !find.isEmpty else {
            errorMessage = L10n.t("msg.enterFind")
            return
        }
        if replaceRegexInvalid {
            errorMessage = L10n.t("msg.regexInvalid")
            return
        }
        // Capture caret before flush so we can advance past the current highlight.
        let fromUTF16: Int = {
            guard let id = selected, editingID == id else { return 0 }
            return highlightAdvanceStart(id: id, forward: forward)
        }()
        let currentId = selected
        guard flushEditing() else { return }

        let keys = rows.map(\.id)
        guard !keys.isEmpty else {
            infoMessage = L10n.t("msg.noMatches")
            return
        }

        // Build scan order of segment indices.
        let startIdx: Int = {
            if let currentId, let i = keys.firstIndex(of: currentId) { return i }
            return forward ? 0 : keys.count - 1
        }()

        if forward {
            // 1) Remainder of current segment
            if let currentId, let hit = matchRange(in: currentId, find: find, startFromUTF16: fromUTF16) {
                revealFindMatch(id: currentId, range: hit)
                return
            }
            // 2) Later segments, then wrap
            for offset in 1...keys.count {
                let id = keys[(startIdx + offset) % keys.count]
                if let hit = matchRange(in: id, find: find, startFromUTF16: 0) {
                    revealFindMatch(id: id, range: hit)
                    return
                }
            }
        } else {
            // Previous: matches before caret in current, else prior segments' last match.
            if let currentId,
               let hit = previousMatchRange(in: currentId, find: find, beforeUTF16: fromUTF16) {
                revealFindMatch(id: currentId, range: hit)
                return
            }
            for offset in 1...keys.count {
                let id = keys[(startIdx - offset + keys.count) % keys.count]
                if let hit = previousMatchRange(in: id, find: find, beforeUTF16: Int.max) {
                    revealFindMatch(id: id, range: hit)
                    return
                }
            }
        }
        infoMessage = L10n.t("msg.noMatches")
    }

    /// Draft UTF-16 index to start searching for the next/prev highlight.
    private func highlightAdvanceStart(id: SegmentKey, forward: Bool) -> Int {
        guard editingID == id, let editor = liveEditor(for: id) else { return 0 }
        let sel = editor.selectedRange()
        let attributed = editor.attributedString()
        if sel.length > 0,
           let draftRange = draftUTF16Range(forAttributedSelection: sel, in: attributed) {
            // Next starts after current highlight; Previous starts at its start.
            return forward ? NSMaxRange(draftRange) : draftRange.location
        }
        let caret = draftUTF16Index(forAttributedLocation: sel.location, in: attributed)
        let draftLen = (draft as NSString).length
        if forward, caret >= draftLen { return 0 }
        return caret
    }

    private func matchRange(in id: SegmentKey, find: String, startFromUTF16: Int) -> NSRange? {
        guard let document, let plan = document.plan(for: id) else { return nil }
        return SearchReplace.firstMatchDraftUTF16(
            in: plan.text,
            pattern: find,
            options: searchOptions,
            startFromUTF16: startFromUTF16
        )
    }

    private func previousMatchRange(in id: SegmentKey, find: String, beforeUTF16: Int) -> NSRange? {
        guard let document, let plan = document.plan(for: id) else { return nil }
        guard let ranges = SearchReplace.matchRanges(
            in: plan.text, pattern: find, options: searchOptions
        ), !ranges.isEmpty else { return nil }
        var last: NSRange?
        for range in ranges {
            let ns = SearchReplace.utf16Range(of: range, in: plan.text)
            if ns.location < beforeUTF16 {
                last = ns
            }
        }
        return last
    }

    /// Select segment and highlight a draft UTF-16 range in the inline editor.
    private func revealFindMatch(id: SegmentKey, range: NSRange) {
        pendingDraftSelection = range
        if selected != id {
            choose(id)
            // Re-apply after choose/startEditing so updateNSView sees the range.
            pendingDraftSelection = range
        }
        if editingID != id {
            startEditing(id)
            pendingDraftSelection = range
        } else {
            // Already editing this segment — force editor to apply pending selection.
            editSession &+= 1
        }
    }

    /// Replace exactly one occurrence via the same document path as Replace All.
    /// Stays on the replaced segment with the new text selected so the user can confirm;
    /// the next Enter/Replace advances past that selection to the following match.
    func replaceCurrent() {
        guard let document else { return }
        let find = findText
        guard !find.isEmpty else {
            errorMessage = L10n.t("msg.enterFind")
            return
        }
        if replaceRegexInvalid {
            errorMessage = L10n.t("msg.regexInvalid")
            return
        }

        // Capture start index while the editor is still alive, then flush like Replace All.
        let currentId = selected
        let startFrom: Int = {
            guard let currentId else { return 0 }
            return draftStartForReplace(id: currentId, find: find)
        }()
        guard flushEditing() else { return }

        let keys = rows.map(\.id)
        guard !keys.isEmpty else {
            infoMessage = L10n.t("msg.noMatches")
            return
        }

        // Try order (one replace only — do not wrap within current on the same click,
        // or the highlight jumps before the user can confirm the result):
        // 1) current from caret/after-selection
        // 2) later segments, then earlier segments
        // 3) finally current from 0 (full-document wrap) if we started mid-segment
        var tryList: [(SegmentKey, Int)] = []
        if let currentId, let i = keys.firstIndex(of: currentId) {
            tryList.append((currentId, startFrom))
            for offset in 1..<keys.count {
                tryList.append((keys[(i + offset) % keys.count], 0))
            }
            if startFrom > 0 {
                tryList.append((currentId, 0))
            }
        } else {
            for id in keys {
                tryList.append((id, 0))
            }
        }

        var sawLocked = false
        var sawUnsafe = false

        for (id, from) in tryList {
            guard let row = rows.first(where: { $0.id == id }), row.isEditable else { continue }

            let before = try? document.makeSnapshot(selection: selected)
            let result: GapReplaceResult
            do {
                result = try document.replaceInTarget(
                    key: id,
                    find: find,
                    replacement: replaceWith,
                    options: searchOptions,
                    tracking: tracking,
                    firstOnly: true,
                    startFromDraftUTF16: from
                )
            } catch {
                continue
            }
            rows = document.rows
            switch result {
            case .applied(_, let count, let sel):
                dirty = true
                // Stay on the segment we just edited so the user can confirm the result.
                // Do not advance to the next Find match — that happens on the *next* Enter.
                if selected != id {
                    choose(id)
                } else {
                    selected = id
                }
                if let before, let after = try? document.makeSnapshot(selection: selected ?? id) {
                    history.record(
                        before: before,
                        after: after,
                        title: L10n.tf("hist.replace", id.mid, count)
                    )
                    syncHistoryUI()
                }
                pendingDraftSelection = sel
                startEditing(id)
                return
            case .skippedLocked:
                sawLocked = true
            case .skippedUnsafe:
                sawUnsafe = true
            case .noMatch, .invalidPattern:
                continue
            }
        }

        if sawLocked {
            errorMessage = L10n.t("msg.replaceLockedRevision")
            NSSound.beep()
        } else if sawUnsafe {
            errorMessage = L10n.t("msg.replaceCrossTag")
        } else {
            infoMessage = L10n.t("msg.noMatches")
        }
    }

    /// Whether `selected` is exactly one match of Replace Find under current options.
    private func selectionEqualsFind(_ selected: String, find: String) -> Bool {
        guard !selected.isEmpty, !find.isEmpty else { return false }
        let opts = searchOptions
        if opts.useRegex || opts.wholeWord {
            guard let ranges = SearchReplace.matchRanges(in: selected, pattern: find, options: opts),
                  ranges.count == 1,
                  ranges[0] == selected.startIndex..<selected.endIndex else {
                return false
            }
            return true
        }
        if opts.caseSensitive {
            return selected == find
        }
        return selected.caseInsensitiveCompare(find) == .orderedSame
    }

    /// UTF-16 draft index to start the next single Replace from (captured before flush).
    ///
    /// Stay-on-result UX:
    /// - Selection *is* the Find match (e.g. after 「下一个」) → start at selection so this
    ///   click replaces that match and then stops with it highlighted.
    /// - Selection is anything else (including the just-replaced span) → start *after*
    ///   the selection so the *next* Enter/Replace advances to the following match.
    private func draftStartForReplace(id: SegmentKey, find: String) -> Int {
        guard editingID == id, let editor = liveEditor(for: id) else { return 0 }
        let sel = editor.selectedRange()
        let attributed = editor.attributedString()
        if sel.length > 0 {
            if let draftRange = draftUTF16Range(forAttributedSelection: sel, in: attributed) {
                let nsDraft = draft as NSString
                let safe = NSIntersectionRange(draftRange, NSRange(location: 0, length: nsDraft.length))
                guard safe.length > 0 else { return 0 }
                let selectedText = nsDraft.substring(with: safe)
                if selectionEqualsFind(selectedText, find: find) {
                    return safe.location
                }
                // After a successful replace the new text is selected; search past it.
                return NSMaxRange(safe)
            }
            return 0
        }
        let caret = draftUTF16Index(forAttributedLocation: sel.location, in: attributed)
        let draftLen = (draft as NSString).length
        if caret >= draftLen { return 0 }
        return caret
    }

    /// Replace All across the whole document (target gaps). Ignores Find/table text filters.
    func replaceAll() {
        guard let document else { return }
        let find = findText
        guard !find.isEmpty else {
            errorMessage = L10n.t("msg.enterFind")
            return
        }
        if replaceRegexInvalid {
            errorMessage = L10n.t("msg.regexInvalid")
            return
        }
        guard flushEditing() else { return }

        let targets = rows
        guard !targets.isEmpty else {
            infoMessage = L10n.t("msg.noMatches")
            return
        }

        let alert = NSAlert()
        alert.messageText = L10n.t("msg.replaceAllTitle")
        alert.informativeText = L10n.tf("msg.replaceAllBody", targets.count)
        alert.addButton(withTitle: L10n.t("msg.replaceAllBtn"))
        alert.addButton(withTitle: L10n.t("alert.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let before = try? document.makeSnapshot(selection: selected)
        var replacedSegments = 0
        var replacementCount = 0
        var skippedUnsafe = 0
        var skippedOther = 0

        for row in targets {
            guard row.isEditable else {
                skippedOther += 1
                continue
            }
            do {
                let result = try document.replaceInTarget(
                    key: row.id,
                    find: find,
                    replacement: replaceWith,
                    options: searchOptions,
                    tracking: tracking
                )
                switch result {
                case .applied(_, let count, _):
                    replacedSegments += 1
                    replacementCount += count
                case .skippedUnsafe:
                    skippedUnsafe += 1
                case .skippedLocked:
                    skippedOther += 1
                case .noMatch:
                    break
                case .invalidPattern:
                    errorMessage = L10n.t("msg.regexInvalid")
                    rows = document.rows
                    return
                }
            } catch {
                skippedOther += 1
            }
        }

        rows = document.rows
        if replacementCount > 0 {
            dirty = true
            if let before, let after = try? document.makeSnapshot(selection: selected) {
                history.record(
                    before: before,
                    after: after,
                    title: L10n.tf("hist.replaceAll", replacementCount, replacedSegments)
                )
                syncHistoryUI()
            }
        }
        infoMessage = L10n.tf(
            "msg.replaceAllDone",
            replacementCount, replacedSegments, skippedUnsafe, skippedOther
        )
    }


    /// Commit the live editor draft into the DOM without leaving edit mode.
    @discardableResult
    private func commitDraftKeepingEditor() -> Bool {
        guard let id = editingID, let document else { return true }
        let editorSnapshot = liveEditor(for: id)?.committedInternalDraft()
        let planText = document.plan(for: id)?.text ?? draft
        let chosen = FlushPolicy.draftToCommit(
            FlushPolicy.Candidates(editor: editorSnapshot, store: draft, plan: planText),
            split: { try document.plan(for: id)?.split($0) ?? [$0] }
        )
        draft = chosen
        do {
            let before = try document.makeSnapshot(selection: selected)
            try document.applyEdit(key: id, draft: chosen, tracking: tracking)
            rows = document.rows
            let after = try document.makeSnapshot(selection: selected)
            if HistoryManager.shouldRecord(before: before, after: after) {
                dirty = true
                history.record(before: before, after: after, title: L10n.tf("hist.edit", id.mid))
                syncHistoryUI()
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Apply bold / italic / underline (Trados-like). Selection optional:
    /// - with selection → wrap that range
    /// - no selection → wrap whole plain segment (or the caret's plain gap); also sticky-type next chars
    /// Word-like Shift+F3: cycle selection (or current word) UPPER → lower → Capitalize.
    func cycleCase() {
        guard !reviewMode, let id = editingID, let editor = liveEditor(for: id) else { return }
        editor.cycleCaseSelection()
    }

    func applyCase(_ style: SegmentTextView.TextCaseStyle) {
        guard !reviewMode, let id = editingID, let editor = liveEditor(for: id) else { return }
        editor.applyCase(style)
    }

    func applyFormat(_ kind: InlineFormatKind) {
        guard let id = editingID, let document else {
            errorMessage = L10n.t("msg.openSegment")
            return
        }
        guard !reviewMode else {
            errorMessage = L10n.t("msg.formatReview")
            return
        }
        guard let editor = liveEditor(for: id) else {
            errorMessage = L10n.t("msg.noEditor")
            return
        }
        guard commitDraftKeepingEditor() else { return }
        guard let plan = document.plan(for: id) else { return }

        let selection = editor.selectedRange()
        let attributed = editor.attributedString()
        let stickyBit: TextFormat = {
            switch kind {
            case .bold: return TextFormat(bold: true)
            case .italic: return TextFormat(italic: true)
            case .underline: return TextFormat(underline: true)
            case .superscript: return TextFormat(position: .superscript)
            case .subscript: return TextFormat(position: .subscript)
            }
        }()
        // Sticky for next keystrokes (works even when segment text is empty).
        editor.stickyFormat = TextFormat.combined([editor.stickyFormat, stickyBit])
        editor.typingAttributes = typingStyle(
            tracking, inheritingFrom: editor, sticky: editor.stickyFormat
        )

        let draftRange: NSRange?
        if selection.length > 0 {
            draftRange = draftUTF16Range(forAttributedSelection: selection, in: attributed)
        } else {
            let caretDraft = draftUTF16Index(
                forAttributedLocation: selection.location,
                in: attributed
            )
            draftRange = FormatTagSupport.rangeForEmptyCaret(plan: plan, caretDraftUTF16: caretDraft)
        }

        guard let draftRange, draftRange.length > 0 else {
            // Empty segment: sticky typing only — no alert.
            return
        }

        do {
            let before = try document.makeSnapshot(selection: selected)
            let newDraft = try document.applyInlineFormat(
                key: id,
                kind: kind,
                draftUTF16Range: draftRange
            )
            rows = document.rows
            formatting = FormattingResolver(document: document.xmlDocument)
            draft = newDraft
            editBaseline = newDraft
            editSession += 1
            dirty = true
            let after = try document.makeSnapshot(selection: selected)
            if HistoryManager.shouldRecord(before: before, after: after) {
                history.record(before: before, after: after, title: L10n.tf("hist.format", {
                    switch kind {
                    case .bold: return L10n.t("menu.bold")
                    case .italic: return L10n.t("menu.italic")
                    case .underline: return L10n.t("menu.underline")
                    case .superscript: return L10n.t("menu.superscript")
                    case .subscript: return L10n.t("menu.subscript")
                    }
                }(), id.mid))
                syncHistoryUI()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - History

    var canUndo: Bool {
        history.canUndo || hasUncommittedEdit
    }

    var canRedo: Bool {
        // Never claim redo while an uncommitted edit would flush and truncate the redo stack.
        !hasUncommittedEdit && history.canRedo
    }

    /// Live editor draft differs from the document baseline for the editing segment.
    /// Does not call `committedInternalDraft` (that unmarks IME); composition counts as dirty.
    private var hasUncommittedEdit: Bool {
        guard let id = editingID, let document else { return false }
        let baseline = document.editorDraft(for: id) ?? ""
        if let editor = liveEditor(for: id) {
            if editor.hasMarkedText() { return true }
            return internalDraft(editor.attributedString()) != baseline
        }
        return draft != baseline
    }

    private func syncHistoryUI() {
        historyEntries = history.entries
        historyPosition = history.position
    }

    /// Session undo. Uncommitted typing is flushed into history first (so one ⌘Z
    /// reverts it); clean editor state is discarded without recording so redo survives.
    func undoLatest() {
        if editingID != nil {
            if hasUncommittedEdit {
                guard flushEditing() else { return }
            } else {
                cancelEdit()
            }
        }
        restoreHistory(history.position - 1, flushFirst: false)
    }

    /// Session redo. Abandon uncommitted editor state without flush — flushing would
    /// record a new entry and wipe the redo tail (the classic flaky-redo bug).
    func redoLatest() {
        if editingID != nil {
            cancelEdit()
        }
        restoreHistory(history.position + 1, flushFirst: false)
    }

    func restoreHistory(_ position: Int, flushFirst: Bool = true) {
        if flushFirst {
            guard flushEditing() else { return }
        }
        guard let document else { return }
        guard let snapshot = history.move(to: position) else { return }
        let keepTracking = tracking
        let keepURL = fileURL
        let keepReview = reviewMode
        do {
            try document.restore(snapshot: snapshot)
            rows = document.rows
            formatting = FormattingResolver(document: document.xmlDocument)
            selected = snapshot.selectionKey.flatMap { key in
                rows.contains(where: { $0.id == key }) ? key : nil
            }
            editingID = nil
            draft = ""
            tracking = keepTracking
            fileURL = keepURL
            reviewMode = keepReview
            dirty = true
            syncHistoryUI()
            if !reviewMode {
                openInlineEditorIfNeeded(for: selected)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
