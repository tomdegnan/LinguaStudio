import XCTest
@testable import LinguaCore
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Tracking OFF: leaving a row must keep Chinese and keep `[]` / tag placeholders.
final class SwitchAwayFlushTests: XCTestCase {

    private let xml = """
    <?xml version="1.0" encoding="utf-8"?>
    <xliff xmlns="urn:oasis:names:tc:xliff:document:1.2" xmlns:sdl="http://sdl.com/FileTypes/SdlXliff/1.0" version="1.2" sdl:version="1.0">
      <file original="m.docx" source-language="fr-FR" target-language="en-US" datatype="x-sdl-plaintext">
        <body>
          <trans-unit id="u4">
            <source>Compte rendu opératoire du 17/03/2026</source>
            <seg-source><mrk mtype="seg" mid="4">Compte rendu opératoire du 17/03/2026</mrk></seg-source>
            <target><mrk mtype="seg" mid="4">Operative report dated 17MAR2026</mrk></target>
            <sdl:seg-defs><sdl:seg id="4" conf="Translated"/></sdl:seg-defs>
          </trans-unit>
          <trans-unit id="u5">
            <source><g id="16">[Redacted]</g></source>
            <seg-source><g id="16"><mrk mtype="seg" mid="5">[Redacted]</mrk></g></seg-source>
            <target><g id="16"><mrk mtype="seg" mid="5">[Redacted]</mrk> </g></target>
            <sdl:seg-defs><sdl:seg id="5" conf="Translated"/></sdl:seg-defs>
          </trans-unit>
          <trans-unit id="u6">
            <source><g id="19">[Redacted]</g></source>
            <seg-source><g id="19"><mrk mtype="seg" mid="6">[Redacted]</mrk></g></seg-source>
            <target><g id="19"><mrk mtype="seg" mid="6">[Redacted]</mrk></g></target>
            <sdl:seg-defs><sdl:seg id="6" conf="Translated"/></sdl:seg-defs>
          </trans-unit>
        </body>
      </file>
      <doc-info><sdl:rev-defs></sdl:rev-defs></doc-info>
    </xliff>
    """

    private let k4 = SegmentKey(unitId: "u4", mid: "4")
    private let k5 = SegmentKey(unitId: "u5", mid: "5")
    private let k6 = SegmentKey(unitId: "u6", mid: "6")

    private func load() throws -> SDLXLIFFDocument {
        try SDLXLIFFDocument(data: Data(xml.utf8), authorName: "UnitTest")
    }

    // MARK: - FlushPolicy

    func testFlushPrefersEditorWhenComplete() throws {
        let plan = try XCTUnwrap(try load().plan(for: k5))
        let chosen = FlushPolicy.draftToCommit(
            .init(editor: "[Redacted]测试", store: "[Redacted]", plan: "[Redacted]"),
            split: { try plan.split($0) }
        )
        XCTAssertEqual(chosen, "[Redacted]测试")
    }

    /// Editor briefly shows stripped "Redacted" (lost brackets) while store still has
    /// the good draft — must NOT commit the stripped editor snapshot.
    func testFlushRejectsStrippedEditorBrackets() throws {
        let plan = try XCTUnwrap(try load().plan(for: k5))
        let chosen = FlushPolicy.draftToCommit(
            .init(editor: "Redacted", store: "[Redacted]测试", plan: "[Redacted]"),
            split: { try plan.split($0) }
        )
        XCTAssertEqual(chosen, "[Redacted]测试")
        XCTAssertTrue(chosen.contains("["))
        XCTAssertTrue(chosen.contains("]"))
        XCTAssertTrue(chosen.contains("测试"))
    }

    /// Editor lost CJK (IME resign race) but store.draft still has it.
    func testFlushPrefersStoreWhenEditorLostCJK() throws {
        let plan = try XCTUnwrap(try load().plan(for: k4))
        let good = "Operative report dated 17MAR2026测试"
        let chosen = FlushPolicy.draftToCommit(
            .init(editor: "Operative report dated 17MAR2026", store: good, plan: "Operative report dated 17MAR2026"),
            split: { try plan.split($0) }
        )
        XCTAssertEqual(chosen, good)
    }

    func testFlushWouldLoseContentHelper() {
        XCTAssertTrue(FlushPolicy.wouldLoseContent(proposed: "Redacted", baseline: "[Redacted]"))
        XCTAssertTrue(FlushPolicy.wouldLoseContent(proposed: "Operative report dated 17MAR2026", baseline: "Operative report dated 17MAR2026测试"))
        XCTAssertFalse(FlushPolicy.wouldLoseContent(proposed: "[Redacted]测试", baseline: "[Redacted]"))
        XCTAssertFalse(FlushPolicy.wouldLoseContent(proposed: "[Redacted]", baseline: "[Redacted]"))
    }

    // MARK: - Document switch-away (tracking OFF)

    /// Edit segment 4 with Chinese, switch to 5 (apply 4), assert 4 still has Chinese.
    func testSwitchAwayKeepsChineseTrackingOff() throws {
        let doc = try load()
        let open4 = try XCTUnwrap(doc.editorDraft(for: k4))
        XCTAssertEqual(open4, "Operative report dated 17MAR2026")

        let typed = open4 + "测试"
        // Simulate flush of leaving segment 4 via FlushPolicy (editor has typed text).
        let plan4 = try XCTUnwrap(doc.plan(for: k4))
        let commit4 = FlushPolicy.draftToCommit(
            .init(editor: typed, store: typed, plan: open4),
            split: { try plan4.split($0) }
        )
        try doc.applyEdit(key: k4, draft: commit4, tracking: false)

        // Open 5 (as choose would).
        let open5 = try XCTUnwrap(doc.editorDraft(for: k5))
        XCTAssertEqual(open5, "[Redacted]")

        let row4 = try XCTUnwrap(doc.rows.first { $0.id == k4 })
        XCTAssertTrue(row4.target.contains("测试"), "segment 4 lost Chinese after switch: \(row4.target)")
        XCTAssertEqual(doc.editorDraft(for: k4), typed)
    }

    /// Edit segment 5 keeping/adding around [Redacted], switch to 4, assert 5 still has [].
    func testSwitchAwayKeepsBracketsTrackingOff() throws {
        let doc = try load()
        let open5 = try XCTUnwrap(doc.editorDraft(for: k5))
        XCTAssertEqual(open5, "[Redacted]")

        let typed = open5 + "测试"
        let plan5 = try XCTUnwrap(doc.plan(for: k5))
        let commit5 = FlushPolicy.draftToCommit(
            .init(editor: typed, store: typed, plan: open5),
            split: { try plan5.split($0) }
        )
        try doc.applyEdit(key: k5, draft: commit5, tracking: false)

        _ = doc.editorDraft(for: k4)
        let row5 = try XCTUnwrap(doc.rows.first { $0.id == k5 })
        XCTAssertTrue(row5.target.contains("["), "lost [: \(row5.target)")
        XCTAssertTrue(row5.target.contains("]"), "lost ]: \(row5.target)")
        XCTAssertTrue(row5.target.contains("测试"), "lost 测试: \(row5.target)")

        let reopen = try XCTUnwrap(doc.editorDraft(for: k5))
        XCTAssertTrue(reopen.hasPrefix("["))
        XCTAssertTrue(reopen.contains("]"))
        XCTAssertTrue(reopen.contains("测试"))
    }

    /// Stripped editor on leave must not wipe brackets that store still has.
    func testSwitchAwayWithStrippedEditorKeepsBrackets() throws {
        let doc = try load()
        let open5 = try XCTUnwrap(doc.editorDraft(for: k5))
        let storeDraft = open5 + "测试" // last onChange before a bad editor snapshot
        let plan5 = try XCTUnwrap(doc.plan(for: k5))
        let commit = FlushPolicy.draftToCommit(
            .init(editor: "Redacted测", store: storeDraft, plan: open5),
            split: { try plan5.split($0) }
        )
        try doc.applyEdit(key: k5, draft: commit, tracking: false)
        let visible = try XCTUnwrap(doc.rows.first { $0.id == k5 }?.target)
        XCTAssertTrue(visible.contains("["))
        XCTAssertTrue(visible.contains("]"))
        XCTAssertTrue(visible.contains("测试"))
    }

    /// Full round-trip: 4→5→4→6 with tracking off.
    func testBidirectionalSwitchKeepsBoth() throws {
        let doc = try load()
        let t4 = try XCTUnwrap(doc.editorDraft(for: k4)) + "中文"
        try doc.applyEdit(key: k4, draft: t4, tracking: false)

        let t5 = try XCTUnwrap(doc.editorDraft(for: k5)) + "测"
        try doc.applyEdit(key: k5, draft: t5, tracking: false)

        XCTAssertTrue(try XCTUnwrap(doc.rows.first { $0.id == k4 }?.target).contains("中文"))
        XCTAssertTrue(try XCTUnwrap(doc.rows.first { $0.id == k5 }?.target).contains("["))
        XCTAssertTrue(try XCTUnwrap(doc.rows.first { $0.id == k5 }?.target).contains("]"))
        XCTAssertTrue(try XCTUnwrap(doc.rows.first { $0.id == k5 }?.target).contains("测"))

        _ = doc.editorDraft(for: k6)
        XCTAssertEqual(doc.editorDraft(for: k4), t4)
        XCTAssertEqual(doc.editorDraft(for: k5), t5)

        let data = try doc.serializedData()
        let reloaded = try SDLXLIFFDocument(data: data, authorName: "UnitTest")
        XCTAssertTrue(try XCTUnwrap(reloaded.editorDraft(for: k4)).contains("中文"))
        let r5 = try XCTUnwrap(reloaded.editorDraft(for: k5))
        XCTAssertTrue(r5.contains("["))
        XCTAssertTrue(r5.contains("]"))
        XCTAssertTrue(r5.contains("测"))
    }

    /// Select/filter remount race: editor+store both "" while plan still has text
    /// must NOT commit empty (that wiped targets when picking Draft rows).
    func testFlushRefusesEmptyLiveOverNonEmptyPlan() throws {
        let plan = try XCTUnwrap(try load().plan(for: k4))
        let planText = plan.text
        XCTAssertFalse(planText.isEmpty)
        let chosen = FlushPolicy.draftToCommit(
            .init(editor: "", store: "", plan: planText),
            split: { try plan.split($0) }
        )
        XCTAssertEqual(chosen, planText)
        XCTAssertFalse(chosen.isEmpty)
    }

    func testFlushRefusesNilEditorEmptyStoreOverPlan() throws {
        let plan = try XCTUnwrap(try load().plan(for: k5))
        let planText = plan.text
        let chosen = FlushPolicy.draftToCommit(
            .init(editor: nil, store: "", plan: planText),
            split: { try plan.split($0) }
        )
        XCTAssertEqual(chosen, planText)
    }

    /// Empty live over empty plan is fine (genuinely empty segment).
    func testFlushAllowsEmptyWhenPlanEmpty() throws {
        let root = XMLElement(name: "target")
        root.addChild(XMLNode.text(withStringValue: "") as! XMLNode)
        // TagPlan on empty target → empty text
        let plan = TagPlan(root)
        XCTAssertEqual(plan.text, "")
        let chosen = FlushPolicy.draftToCommit(
            .init(editor: "", store: "", plan: ""),
            split: { try plan.split($0) }
        )
        XCTAssertEqual(chosen, "")
    }

    /// Applying the raced empty commit must not wipe; use FlushPolicy then apply.
    func testSwitchAwayEmptyRaceDoesNotWipeDocument() throws {
        let doc = try load()
        let before = try XCTUnwrap(doc.editorDraft(for: k4))
        XCTAssertFalse(before.isEmpty)
        let plan4 = try XCTUnwrap(doc.plan(for: k4))
        let commit = FlushPolicy.draftToCommit(
            .init(editor: "", store: "", plan: before),
            split: { try plan4.split($0) }
        )
        try doc.applyEdit(key: k4, draft: commit, tracking: false)
        XCTAssertEqual(doc.editorDraft(for: k4), before)
        XCTAssertEqual(doc.rows.first { $0.id == k4 }?.target.contains("Operative") , true)
    }

}
