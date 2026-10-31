import XCTest
@testable import LinguaCore
import Foundation

/// Session history must record switch-away flushes and undo/redo must restore targets.
final class HistoryUndoTests: XCTestCase {

    private let xml = """
    <?xml version="1.0" encoding="utf-8"?>
    <xliff xmlns="urn:oasis:names:tc:xliff:document:1.2" xmlns:sdl="http://sdl.com/FileTypes/SdlXliff/1.0" version="1.2" sdl:version="1.0">
      <file original="m.docx" source-language="fr-FR" target-language="en-US" datatype="x-sdl-plaintext">
        <body>
          <trans-unit id="u4">
            <source>Compte rendu</source>
            <seg-source><mrk mtype="seg" mid="4">Compte rendu</mrk></seg-source>
            <target><mrk mtype="seg" mid="4">Operative report</mrk></target>
            <sdl:seg-defs><sdl:seg id="4" conf="Translated"/></sdl:seg-defs>
          </trans-unit>
          <trans-unit id="u5">
            <source><g id="16">[Redacted]</g></source>
            <seg-source><g id="16"><mrk mtype="seg" mid="5">[Redacted]</mrk></g></seg-source>
            <target><g id="16"><mrk mtype="seg" mid="5">[Redacted]</mrk></g></target>
            <sdl:seg-defs><sdl:seg id="5" conf="Translated"/></sdl:seg-defs>
          </trans-unit>
        </body>
      </file>
      <doc-info><sdl:rev-defs></sdl:rev-defs></doc-info>
    </xliff>
    """

    private let k4 = SegmentKey(unitId: "u4", mid: "4")
    private let k5 = SegmentKey(unitId: "u5", mid: "5")

    private func load() throws -> SDLXLIFFDocument {
        try SDLXLIFFDocument(data: Data(xml.utf8), authorName: "UnitTest")
    }

    /// Simulate Store.flushEditing history recording after switch-away (tracking OFF).
    private func flushCommit(
        _ doc: SDLXLIFFDocument,
        key: SegmentKey,
        draft: String,
        history: HistoryManager,
        selection: SegmentKey?
    ) throws {
        let before = try doc.makeSnapshot(selection: selection)
        try doc.applyEdit(key: key, draft: draft, tracking: false)
        let after = try doc.makeSnapshot(selection: selection)
        XCTAssertTrue(HistoryManager.shouldRecord(before: before, after: after))
        history.record(before: before, after: after, title: "编辑句段 \(key.mid)")
    }

    func testSwitchAwayFlushRecordsAndUndoRestoresChinese() throws {
        let doc = try load()
        let history = HistoryManager()
        let open4 = try XCTUnwrap(doc.editorDraft(for: k4))
        let typed = open4 + "测试"

        try flushCommit(doc, key: k4, draft: typed, history: history, selection: k4)
        XCTAssertEqual(history.position, 1)
        XCTAssertTrue(history.canUndo)
        XCTAssertTrue(try XCTUnwrap(doc.rows.first { $0.id == k4 }?.target).contains("测试"))

        // Switch-away to 5 (open editor conceptually) — prior edit already in history.
        let open5 = try XCTUnwrap(doc.editorDraft(for: k5))
        XCTAssertEqual(open5, "[Redacted]")

        // Undo must restore segment 4 target.
        let snap = try XCTUnwrap(history.move(to: 0))
        try doc.restore(snapshot: snap)
        let restored = try XCTUnwrap(doc.editorDraft(for: k4))
        XCTAssertEqual(restored, open4)
        XCTAssertFalse(restored.contains("测试"))
        XCTAssertTrue(history.canRedo)
    }

    func testUndoRedoRoundTripKeepsBrackets() throws {
        let doc = try load()
        let history = HistoryManager()
        let open5 = try XCTUnwrap(doc.editorDraft(for: k5))
        let typed = open5 + "测"

        try flushCommit(doc, key: k5, draft: typed, history: history, selection: k5)
        XCTAssertTrue(try XCTUnwrap(doc.editorDraft(for: k5)).contains("["))
        XCTAssertTrue(try XCTUnwrap(doc.editorDraft(for: k5)).contains("]"))

        let beforeUndo = try XCTUnwrap(history.move(to: 0))
        try doc.restore(snapshot: beforeUndo)
        XCTAssertEqual(doc.editorDraft(for: k5), open5)

        let afterRedo = try XCTUnwrap(history.move(to: 1))
        try doc.restore(snapshot: afterRedo)
        let again = try XCTUnwrap(doc.editorDraft(for: k5))
        XCTAssertTrue(again.contains("["))
        XCTAssertTrue(again.contains("]"))
        XCTAssertTrue(again.contains("测"))
    }

    func testIdenticalFlushDoesNotRecord() throws {
        let doc = try load()
        let history = HistoryManager()
        let open4 = try XCTUnwrap(doc.editorDraft(for: k4))
        let before = try doc.makeSnapshot(selection: k4)
        try doc.applyEdit(key: k4, draft: open4, tracking: false)
        let after = try doc.makeSnapshot(selection: k4)
        XCTAssertFalse(HistoryManager.shouldRecord(before: before, after: after))
        history.record(before: before, after: after, title: "noop")
        XCTAssertEqual(history.position, 0)
        XCTAssertFalse(history.canUndo)
    }

    func testRedoTailSurvivesWhenNoNewRecord() throws {
        let doc = try load()
        let history = HistoryManager()
        let open4 = try XCTUnwrap(doc.editorDraft(for: k4))
        try flushCommit(doc, key: k4, draft: open4 + "A", history: history, selection: k4)
        try flushCommit(doc, key: k4, draft: open4 + "AB", history: history, selection: k4)
        XCTAssertEqual(history.position, 2)
        _ = history.move(to: 1) // undo one → redo available
        XCTAssertTrue(history.canRedo)
        // Simulate redoLatest abandoning a clean editor without flush/record:
        XCTAssertEqual(history.entries.count, 2)
        let redone = try XCTUnwrap(history.move(to: 2))
        try doc.restore(snapshot: redone)
        XCTAssertTrue(try XCTUnwrap(doc.editorDraft(for: k4)).hasSuffix("AB"))
    }

    func testHistoryDetailShowsBeforeAfterTarget() throws {
        let doc = try load()
        let history = HistoryManager()
        let before = try doc.makeSnapshot(selection: k5)
        try doc.applyEdit(key: k5, draft: "[redacted]", tracking: false)
        let after = try doc.makeSnapshot(selection: k5)
        history.record(before: before, after: after, title: "替换句段 5 (1)")
        let entry = try XCTUnwrap(history.entries.last)
        XCTAssertFalse(entry.detail.isEmpty, "detail should describe the text change")
        XCTAssertTrue(entry.detail.contains("→"), "detail: \(entry.detail)")
        XCTAssertTrue(
            entry.detail.lowercased().contains("redacted"),
            "detail should include target text: \(entry.detail)"
        )
    }

    func testHistoryDetailShowsStatusChangeWhenTargetUnchanged() throws {
        let key = k4.description
        let before = EditSnapshot(
            data: Data(),
            selectionKey: k4,
            statuses: [key: SegmentStatus.draft.rawValue],
            targets: [key: "Operative report"]
        )
        let after = EditSnapshot(
            data: Data(),
            selectionKey: k4,
            statuses: [key: SegmentStatus.confirmed.rawValue],
            targets: [key: "Operative report"]
        )
        let detail = HistoryDiff.preview(before: before, after: after)
        XCTAssertTrue(detail.contains("→"), "detail: \(detail)")
        XCTAssertTrue(detail.contains("已确认"), "detail: \(detail)")
        XCTAssertTrue(detail.contains("草稿"), "detail: \(detail)")
    }

    func testHistoryTruncateLongStrings() {
        let long = String(repeating: "a", count: 80)
        let t = HistoryDiff.truncate(long, 36)
        XCTAssertTrue(t.hasPrefix("“"))
        XCTAssertTrue(t.hasSuffix("…”"))
        XCTAssertLessThan(t.count, 50)
    }

}
