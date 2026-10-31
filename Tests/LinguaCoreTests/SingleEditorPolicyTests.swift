import XCTest
@testable import LinguaCore
import Foundation

/// Single shared-editor invariants + flush-before-choose with tracking OFF.
final class SingleEditorPolicyTests: XCTestCase {

    private let k4 = SegmentKey(unitId: "u4", mid: "4")
    private let k5 = SegmentKey(unitId: "u5", mid: "5")

    func testChooseFlushesBeforeActivatingNext() {
        var flushedKeys: [SegmentKey?] = []
        let current: SegmentKey? = k4
        let transition = SingleEditorPolicy.choose(
            current: current,
            next: k5,
            flush: {
                flushedKeys.append(current)
                return true
            }
        )
        XCTAssertTrue(transition.flushed)
        XCTAssertEqual(transition.active, k5)
        XCTAssertEqual(flushedKeys, [k4], "must flush current before activating next")
    }

    func testChooseKeepsCurrentWhenFlushFails() {
        let transition = SingleEditorPolicy.choose(
            current: k4,
            next: k5,
            flush: { false }
        )
        XCTAssertFalse(transition.flushed)
        XCTAssertEqual(transition.active, k4)
    }

    func testOnlyOneEditorConceptuallyActive() {
        XCTAssertTrue(SingleEditorPolicy.isSingleActive(editingID: nil, selected: k4))
        XCTAssertTrue(SingleEditorPolicy.isSingleActive(editingID: k4, selected: k4))
        XCTAssertFalse(SingleEditorPolicy.isSingleActive(editingID: k4, selected: k5))
        XCTAssertFalse(SingleEditorPolicy.isSingleActive(editingID: k5, selected: nil))
    }

    func testFlushBeforeChooseKeepsChineseAndBracketsTrackingOff() throws {
        let xml = """
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
        let doc = try SDLXLIFFDocument(data: Data(xml.utf8), authorName: "UnitTest")
        var editing: SegmentKey? = k4
        var storeDraft = try XCTUnwrap(doc.editorDraft(for: k4)) + "测试"

        // Simulate single-editor choose(4→5): flush current via FlushPolicy, then activate 5.
        let transition = SingleEditorPolicy.choose(
            current: editing,
            next: k5,
            flush: {
                let plan = doc.plan(for: k4)
                let commit = FlushPolicy.draftToCommit(
                    .init(editor: storeDraft, store: storeDraft, plan: plan?.text ?? storeDraft),
                    split: { try plan?.split($0) ?? [$0] }
                )
                do {
                    try doc.applyEdit(key: k4, draft: commit, tracking: false)
                    editing = nil
                    return true
                } catch {
                    return false
                }
            }
        )
        XCTAssertTrue(transition.flushed)
        XCTAssertEqual(transition.active, k5)
        editing = transition.active
        storeDraft = try XCTUnwrap(doc.editorDraft(for: k5))
        XCTAssertTrue(SingleEditorPolicy.isSingleActive(editingID: editing, selected: k5))

        let row4 = try XCTUnwrap(doc.rows.first { $0.id == k4 })
        XCTAssertTrue(row4.target.contains("测试"), "Chinese must survive 4→5: \(row4.target)")

        // Edit 5 with brackets + Chinese, switch back to 4.
        storeDraft = storeDraft + "测"
        let back = SingleEditorPolicy.choose(
            current: editing,
            next: k4,
            flush: {
                let plan = doc.plan(for: k5)
                let commit = FlushPolicy.draftToCommit(
                    .init(editor: storeDraft, store: storeDraft, plan: plan?.text ?? storeDraft),
                    split: { try plan?.split($0) ?? [$0] }
                )
                do {
                    try doc.applyEdit(key: k5, draft: commit, tracking: false)
                    editing = nil
                    return true
                } catch {
                    return false
                }
            }
        )
        XCTAssertTrue(back.flushed)
        let row5 = try XCTUnwrap(doc.rows.first { $0.id == k5 })
        XCTAssertTrue(row5.target.contains("["), row5.target)
        XCTAssertTrue(row5.target.contains("]"), row5.target)
        XCTAssertTrue(row5.target.contains("测"), row5.target)
        XCTAssertTrue(try XCTUnwrap(doc.rows.first { $0.id == k4 }?.target).contains("测试"))
    }
}
