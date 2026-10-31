import XCTest
@testable import LinguaCore
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// "选中就变图 2": row shows "[Name] 测试 测试", re-selecting it opened an editor that
/// showed only "[Name]". Covers the editor sync rule and the draft used to open the editor.
final class ReselectSegmentTests: XCTestCase {

    /// Mirrors the user's file: <g> wraps the seg <mrk> inside <target>; mids 7/8 share a TU.
    private let xml = """
    <?xml version="1.0" encoding="utf-8"?>
    <xliff xmlns="urn:oasis:names:tc:xliff:document:1.2" xmlns:sdl="http://sdl.com/FileTypes/SdlXliff/1.0" version="1.2" sdl:version="1.0">
      <file original="m.docx" source-language="fr-FR" target-language="en-US" datatype="x-sdl-plaintext">
        <body>
          <trans-unit id="u6">
            <source><g id="19">[Redacted]</g></source>
            <seg-source><g id="19"><mrk mtype="seg" mid="6">[Redacted]</mrk></g></seg-source>
            <target><g id="19"><mrk mtype="seg" mid="6">[Redacted]</mrk></g></target>
            <sdl:seg-defs><sdl:seg id="6" conf="Translated"/></sdl:seg-defs>
          </trans-unit>
          <trans-unit id="u7">
            <source>DIAGNOSTIC : GONARTHROSE</source>
            <seg-source><mrk mtype="seg" mid="7">DIAGNOSTIC :</mrk> <mrk mtype="seg" mid="8">GONARTHROSE</mrk></seg-source>
            <target><mrk mtype="seg" mid="7">DIAGNOSIS:</mrk> <mrk mtype="seg" mid="8">KNEE OSTEOARTHRITIS</mrk></target>
            <sdl:seg-defs><sdl:seg id="7" conf="Translated"/><sdl:seg id="8" conf="Translated"/></sdl:seg-defs>
          </trans-unit>
        </body>
      </file>
      <doc-info><sdl:rev-defs></sdl:rev-defs></doc-info>
    </xliff>
    """

    private let k6 = SegmentKey(unitId: "u6", mid: "6")
    private let k7 = SegmentKey(unitId: "u7", mid: "7")

    // MARK: - Editor sync rule (RichSegmentEditor.updateNSView)

    private func state(view: String, store: String, last: String?, seg: SegmentKey? = nil,
                       session: Int? = 1, composing: Bool = false) -> EditorSync.State {
        EditorSync.State(
            viewDraft: view, storeDraft: store, lastPushedDraft: last,
            renderedSegment: seg ?? k6, renderedSession: session,
            segment: k6, session: 1, composing: composing
        )
    }

    /// Failing case of the old rule: store draft == lastPushedDraft, but the (reused/stale)
    /// text view shows only the name. Old rule kept the stale view; new rule resets it.
    func testStaleViewWithMatchingLastPushedIsReset() {
        let s = state(view: "[Redacted]", store: "[Redacted] 测试 测试", last: "[Redacted] 测试 测试")
        XCTAssertFalse(EditorSync.legacyNeedsReset(s), "precondition: legacy rule shows stale text")
        XCTAssertTrue(EditorSync.needsReset(s))
    }

    func testNewSegmentOrSessionAlwaysResets() {
        let same = "[Redacted] 测试 测试"
        XCTAssertTrue(EditorSync.needsReset(state(view: same, store: same, last: same, seg: k7)))
        XCTAssertTrue(EditorSync.needsReset(state(view: same, store: same, last: same, session: 0)))
        XCTAssertTrue(EditorSync.needsReset(state(view: same, store: same, last: nil)))
    }

    func testSteadyTypingDoesNotReset() {
        let s = "[Redacted] 测试"
        XCTAssertFalse(EditorSync.needsReset(state(view: s, store: s, last: s)))
    }

    func testIMECompositionNeverResets() {
        XCTAssertFalse(EditorSync.needsReset(
            state(view: "[Redacted]ce shi", store: "[Redacted]", last: nil, composing: true)
        ))
    }

    /// After IME confirms 测试, the text view already has Chinese while a queued SwiftUI
    /// frame may still carry the pre-commit store draft. Eager reset wiped the Chinese;
    /// the current rule must keep the view.
    func testIMECommitViewAheadOfStoreIsNotReset() {
        let s = state(
            view: "[Redacted]测试 what???",
            store: "[Redacted]",
            last: "[Redacted]测试 what???"
        )
        XCTAssertTrue(EditorSync.eagerNeedsReset(s), "precondition: eager rule wipes IME commit")
        XCTAssertFalse(EditorSync.needsReset(s))
    }

    func testUndoStoreAheadOfViewDoesReset() {
        let s = state(
            view: "[Redacted]测试",
            store: "[Redacted]",
            last: "[Redacted]测试"
        )
        // view == last, store behind/ahead ambiguity: view is authority → no reset.
        // True undo sets a new session (tested above). External store change while view
        // still shows last push but store differs AND view != last is the stale path.
        XCTAssertFalse(EditorSync.needsReset(s))
        let stale = state(view: "[Redacted]", store: "[Redacted]测试", last: "[Redacted]测试")
        XCTAssertTrue(EditorSync.needsReset(stale))
    }

    // MARK: - Draft used to (re)open the editor

    private func load() throws -> SDLXLIFFDocument {
        try SDLXLIFFDocument(data: Data(xml.utf8), authorName: "UnitTest")
    }

    private func reselectCycle(tracking: Bool) throws {
        let doc = try load()
        let open1 = try XCTUnwrap(doc.editorDraft(for: k6))
        XCTAssertEqual(open1, "[Redacted]")

        // type → click row 7 (flush) → click row 6 again
        try doc.applyEdit(key: k6, draft: open1 + " 测试 测试", tracking: tracking)
        _ = try XCTUnwrap(doc.editorDraft(for: k7))
        let row6 = try XCTUnwrap(doc.rows.first { $0.id == k6 })
        XCTAssertTrue(row6.target.contains("测试 测试"), "row display lost text: \(row6.target)")

        let open2 = try XCTUnwrap(doc.editorDraft(for: k6))
        XCTAssertTrue(open2.contains("测试 测试"), "editor reopened without the Chinese: \(open2)")
        let plan = try XCTUnwrap(doc.plan(for: k6))
        XCTAssertTrue(try plan.split(open2).joined().contains("测试 测试"))

        // Flushing the unchanged reopened draft must not change anything.
        let before = try doc.serializedData()
        try doc.applyEdit(key: k6, draft: open2, tracking: tracking)
        XCTAssertEqual(try doc.serializedData(), before)

        // Leave and come back once more, then save/reload.
        _ = doc.editorDraft(for: k7)
        XCTAssertEqual(doc.editorDraft(for: k6), open2)
        let reloaded = try SDLXLIFFDocument(data: doc.serializedData(), authorName: "UnitTest")
        XCTAssertTrue(try XCTUnwrap(reloaded.editorDraft(for: k6)).contains("测试 测试"))
        XCTAssertEqual(reloaded.rows.first { $0.id == k7 }?.target, "DIAGNOSIS:")
    }

    func testReselectKeepsChineseTrackingOff() throws { try reselectCycle(tracking: false) }
    func testReselectKeepsChineseTrackingOn() throws { try reselectCycle(tracking: true) }

    /// Video repro: tracking on, append CJK then ASCII, flush, reopen draft from DOM.
    func testVideoSequenceCJKThenASCIITrackingOn() throws {
        let doc = try load()
        let open1 = try XCTUnwrap(doc.editorDraft(for: k6))
        let typed = open1 + "测试 what???"
        try doc.applyEdit(key: k6, draft: typed, tracking: true)

        let visible = try XCTUnwrap(doc.rows.first { $0.id == k6 }?.target)
        XCTAssertTrue(visible.contains("测试"), "visible lost 测试: \(visible)")
        XCTAssertTrue(visible.contains("what???"), "visible lost ASCII: \(visible)")

        let open2 = try XCTUnwrap(doc.editorDraft(for: k6))
        XCTAssertTrue(open2.contains("测试"), "reopen draft lost 测试: \(open2)")
        XCTAssertTrue(open2.contains("what???"), "reopen draft lost ASCII: \(open2)")
        XCTAssertTrue(open2.contains("⟦"), "reopen draft missing revision tokens: \(open2)")

        let xml = try XCTUnwrap(doc.plan(for: k6)).root.xmlString
        XCTAssertTrue(xml.contains("测试"), "file XML lost 测试: \(xml)")
        XCTAssertTrue(xml.contains("x-sdl-added"), "expected added revision marker")

        // Second reselect cycle must be a no-op on the DOM.
        let before = try doc.serializedData()
        try doc.applyEdit(key: k6, draft: open2, tracking: true)
        XCTAssertEqual(try doc.serializedData(), before)
        XCTAssertEqual(doc.editorDraft(for: k6), open2)
    }

    /// Bug A: `[Redacted]` must keep ASCII brackets when opening the editor draft.
    func testBracketsPreservedOnEditorDraft() throws {
        let doc = try load()
        let key = SegmentKey(unitId: "u6", mid: "6")
        let draft = try XCTUnwrap(doc.editorDraft(for: key))
        XCTAssertEqual(draft, "[Redacted]")
        XCTAssertTrue(draft.hasPrefix("["))
        XCTAssertTrue(draft.hasSuffix("]"))
        let plan = try XCTUnwrap(doc.plan(for: key))
        XCTAssertEqual(try plan.split(draft).joined(), "[Redacted]")
    }

    /// Medical-file shape: <g> wraps <mrk>[Redacted]</mrk> (mid 5 has a trailing space inside g).
    func testBracketsPreservedForGWrappedRedacted() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <xliff xmlns="urn:oasis:names:tc:xliff:document:1.2" xmlns:sdl="http://sdl.com/FileTypes/SdlXliff/1.0" version="1.2" sdl:version="1.0">
          <file original="m.docx" source-language="fr-FR" target-language="en-US" datatype="x-sdl-plaintext">
            <body>
              <trans-unit id="u5">
                <source><g id="16">[Redacted]</g></source>
                <seg-source><g id="16"><mrk mtype="seg" mid="5">[Redacted]</mrk></g></seg-source>
                <target><g id="16"><mrk mtype="seg" mid="5">[Redacted]</mrk> </g></target>
                <sdl:seg-defs><sdl:seg id="5" conf="Translated"/></sdl:seg-defs>
              </trans-unit>
            </body>
          </file>
          <doc-info><sdl:rev-defs></sdl:rev-defs></doc-info>
        </xliff>
        """
        let doc = try SDLXLIFFDocument(data: Data(xml.utf8), authorName: "UnitTest")
        let key = SegmentKey(unitId: "u5", mid: "5")
        let draft = try XCTUnwrap(doc.editorDraft(for: key))
        XCTAssertEqual(draft, "[Redacted]", "g-wrapped mrk lost brackets: \(draft)")
        XCTAssertEqual(doc.rows.first { $0.id == key }?.target, "[Redacted]")
        try doc.applyEdit(key: key, draft: draft, tracking: true)
        XCTAssertEqual(doc.editorDraft(for: key), "[Redacted]")
        try doc.applyEdit(key: key, draft: draft + " 测试", tracking: true)
        let open2 = try XCTUnwrap(doc.editorDraft(for: key))
        XCTAssertTrue(open2.hasPrefix("["), "after tracked append lost [: \(open2)")
        XCTAssertTrue(open2.contains("]"), "after tracked append lost ]: \(open2)")
        XCTAssertTrue(open2.contains("测试"), "after tracked append lost 测试: \(open2)")
        let visible = try XCTUnwrap(doc.rows.first { $0.id == key }?.target)
        XCTAssertTrue(visible.hasPrefix("["))
        XCTAssertTrue(visible.contains("]"))
        XCTAssertTrue(visible.contains("测试"))
    }


    func testIMENeverDeletesOnNewComposition() {
        // Caret just before `]` (index 9 of "[Redacted]") — the video failure mode.
        let caret = NSRange(location: 9, length: 0)
        let requested = NSRange(location: 9, length: 1) // would have eaten `]`
        let safe = IMEEditPolicy.replacementRange(
            requested: requested, caret: caret, marked: nil, composing: false
        )
        XCTAssertEqual(safe.length, 0)
        XCTAssertEqual(safe.location, 9)
    }

    func testIMEContinuesOverMarkedRangeOnly() {
        let caret = NSRange(location: 12, length: 0)
        let marked = NSRange(location: 9, length: 3) // "ce "
        let safe = IMEEditPolicy.replacementRange(
            requested: NSRange(location: NSNotFound, length: 0),
            caret: caret, marked: marked, composing: true
        )
        XCTAssertEqual(safe, marked)
    }

    func testOpeningCaretIsAlwaysAtEnd() {
        XCTAssertEqual(IMEEditPolicy.openingCaretLocation(textLength: 10), 10)
        XCTAssertEqual(IMEEditPolicy.openingCaretLocation(textLength: 0), 0)
    }

}
