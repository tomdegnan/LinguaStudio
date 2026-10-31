import XCTest
@testable import LinguaCore
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Reproduces "切句或确认后丢字" style losses around track-changes + re-edit.
final class TrackingEditLossTests: XCTestCase {

    private func sampleURL() -> URL {
        if let url = Bundle.module.url(forResource: "sample", withExtension: "sdlxliff") {
            return url
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/sample.sdlxliff")
    }

    private func load() throws -> SDLXLIFFDocument {
        try SDLXLIFFDocument(data: Data(contentsOf: sampleURL()), authorName: "UnitTest")
    }

    private func key(_ mid: String, unit: String = "tu1") -> SegmentKey {
        SegmentKey(unitId: unit, mid: mid)
    }

    /// Append CJK with tracking ON, rebuild plan, assert text survives in plan + visibleText.
    func testTrackingAppendCJKSurvivesPlanRebuild() throws {
        let doc = try load()
        let id = key("1")
        let plan0 = try XCTUnwrap(doc.plan(for: id))
        let original = plan0.text
        let draft1 = original + " 测试一下效果"

        try doc.applyEdit(key: id, draft: draft1, tracking: true)

        let plan1 = try XCTUnwrap(doc.plan(for: id))
        let visible = try XCTUnwrap(doc.rows.first { $0.id == id }?.target)

        XCTAssertTrue(visible.contains("测试一下效果"), "visibleText lost CJK: \(visible)")
        XCTAssertTrue(plan1.text.contains("测试一下效果"), "plan.text lost CJK: \(plan1.text)")
        // Revision markers become tokens — draft round-trip must keep CJK in a gap.
        let parts = try plan1.split(plan1.text)
        XCTAssertTrue(parts.joined().contains("测试一下效果"))
        XCTAssertTrue(RevisionFactory.hasPending(in: plan1.root))
    }

    /// Simulate: edit+track → "confirm" (status only) → open plan again → append more → save/reload.
    func testTrackingEditConfirmReeditAppend() throws {
        let doc = try load()
        let id = key("1")
        let p0 = try XCTUnwrap(doc.plan(for: id))

        try doc.applyEdit(key: id, draft: p0.text + " 测试一下效果", tracking: true)
        doc.confirm(key: id)

        let p1 = try XCTUnwrap(doc.plan(for: id))
        XCTAssertTrue(p1.text.contains("测试一下效果"))

        // Second session starts from plan.text (as Store.beginEditing / openInlineEditor does).
        let draft2 = p1.text + "再改"
        try doc.applyEdit(key: id, draft: draft2, tracking: true)

        let p2 = try XCTUnwrap(doc.plan(for: id))
        let visible = try XCTUnwrap(doc.rows.first { $0.id == id }?.target)
        XCTAssertTrue(visible.contains("测试一下效果"), "lost first CJK after re-edit: \(visible)")
        XCTAssertTrue(visible.contains("再改"), "lost second append: \(visible)")
        XCTAssertTrue(p2.text.contains("测试一下效果"))
        XCTAssertTrue(p2.text.contains("再改"))

        let data = try doc.serializedData()
        let reloaded = try SDLXLIFFDocument(data: data, authorName: "UnitTest")
        let again = try XCTUnwrap(reloaded.rows.first { $0.id == id }?.target)
        XCTAssertTrue(again.contains("测试一下效果"))
        XCTAssertTrue(again.contains("再改"))
    }

    /// Re-edit with tracking OFF after a tracked append must not drop the added text.
    func testReeditWithoutTrackingKeepsPriorAddedText() throws {
        let doc = try load()
        let id = key("1")
        let p0 = try XCTUnwrap(doc.plan(for: id))
        try doc.applyEdit(key: id, draft: p0.text + " 测试一下效果", tracking: true)

        let p1 = try XCTUnwrap(doc.plan(for: id))
        // Append outside revision tokens (at end of plan.text).
        try doc.applyEdit(key: id, draft: p1.text + "XYZ", tracking: false)

        let visible = try XCTUnwrap(doc.rows.first { $0.id == id }?.target)
        XCTAssertTrue(visible.contains("测试一下效果"))
        XCTAssertTrue(visible.contains("XYZ"))
    }

    /// Using visibleText (no tokens) as the next draft must fail closed — not silently strip tags/revisions.
    func testVisibleTextDraftAgainstRevisionPlanThrows() throws {
        let doc = try load()
        let id = key("1")
        let p0 = try XCTUnwrap(doc.plan(for: id))
        try doc.applyEdit(key: id, draft: p0.text + " 测试", tracking: true)

        let visible = try XCTUnwrap(doc.rows.first { $0.id == id }?.target)
        // visible has no ⟦tokens⟧; apply must refuse rather than corrupt.
        XCTAssertThrowsError(try doc.applyEdit(key: id, draft: visible + "x", tracking: false))
    }

    /// Replace-middle with tracking: deleted text stays in plan.text; visibleText drops it.
    /// Also guards CJK compounds (你好→您好) so the whole word is one del/add pair.
    func testTrackingReplaceKeepsDeletedInPlanTextOnly() throws {
        let doc = try load()
        let id = key("1")
        let p0 = try XCTUnwrap(doc.plan(for: id))
        // Target starts with "你好 " — replace that prefix.
        let draft = p0.text.replacingOccurrences(of: "你好", with: "您好")
        try doc.applyEdit(key: id, draft: draft, tracking: true)

        let p1 = try XCTUnwrap(doc.plan(for: id))
        let visible = try XCTUnwrap(doc.rows.first { $0.id == id }?.target)
        XCTAssertEqual(visible.contains("您好"), true)
        XCTAssertFalse(visible.contains("你好"), "visibleText should hide deleted")
        XCTAssertTrue(p1.text.contains("你好"), "plan.text still carries deleted run for TC display")
        XCTAssertTrue(p1.text.contains("您好"))

        // CJK compound must not be split (del 你 / add 您 / bare 好).
        let xml = p1.root.xmlString
        XCTAssertTrue(
            xml.contains(">你好</") || xml.contains(">你好<"),
            "expected whole deleted run 你好, got: \(xml)"
        )
        XCTAssertTrue(
            xml.contains(">您好</") || xml.contains(">您好<"),
            "expected whole added run 您好, got: \(xml)"
        )

        // Round-trip plan.text unchanged must be a no-op.
        try doc.applyEdit(key: id, draft: p1.text, tracking: true)
        let visible2 = try XCTUnwrap(doc.rows.first { $0.id == id }?.target)
        XCTAssertEqual(visible2, visible)
    }

    /// Revision gaps: tracking OFF silently keeps original; tracking ON edits in place.
    func testExistingPendingRevisionGapsRequireTracking() throws {
        let doc = try load()
        let id = key("3", unit: "tu3")
        let plan = try XCTUnwrap(doc.plan(for: id))
        XCTAssertTrue(RevisionFactory.hasPending(in: plan.root))
        let beforeText = plan.text

        var parts = try plan.split(plan.text)
        let idx = try XCTUnwrap(plan.revisionGaps.firstIndex(of: true))
        let original = parts[idx]
        parts[idx] = original + "!"
        var rebuilt = parts[0]
        for i in plan.tokens.indices {
            rebuilt += plan.tokens[i] + parts[i + 1]
        }
        // OFF: no throw, revision text unchanged (illegal edits discarded).
        XCTAssertNoThrow(try doc.applyEdit(key: id, draft: rebuilt, tracking: false))
        let planOff = try XCTUnwrap(doc.plan(for: id))
        XCTAssertEqual(planOff.text, beforeText)
        // ON: in-place edit applies.
        XCTAssertNoThrow(try doc.applyEdit(key: id, draft: rebuilt, tracking: true))
        let planOn = try XCTUnwrap(doc.plan(for: id))
        XCTAssertTrue(planOn.text.contains(original + "!"))
        XCTAssertTrue(RevisionFactory.hasPending(in: planOn.root))
    }

    /// Bracket / literal characters around tags must survive tracking edit (Redacted-style).
    func testLiteralsAndTagsSurviveTracking() throws {
        let doc = try load()
        let id = key("1")
        let p0 = try XCTUnwrap(doc.plan(for: id))
        // Append bracketed literal after existing tagged content.
        let draft = p0.text + " [Redacted] 测试"
        try doc.applyEdit(key: id, draft: draft, tracking: true)
        let p1 = try XCTUnwrap(doc.plan(for: id))
        let visible = try XCTUnwrap(doc.rows.first { $0.id == id }?.target)
        XCTAssertTrue(visible.contains("[Redacted]"))
        XCTAssertTrue(visible.contains("测试"))
        XCTAssertTrue(p1.text.contains("[Redacted]"))
        // g tag still present
        let gCount = elementsBelow(p1.root).filter { xmlLocalName($0) == "g" }.count
        XCTAssertEqual(gCount, 1)
    }

    /// confirmAndNext-style double flush: second flush with editingID nil is no-op; no duplication.
    func testDoubleApplySameTrackedDraftDoesNotDuplicate() throws {
        let doc = try load()
        let id = key("1")
        let p0 = try XCTUnwrap(doc.plan(for: id))
        let draft = p0.text + " 测试一下效果"
        try doc.applyEdit(key: id, draft: draft, tracking: true)
        let after1 = try XCTUnwrap(doc.rows.first { $0.id == id }?.target)

        let p1 = try XCTUnwrap(doc.plan(for: id))
        // Second apply of the new plan's own text (flush no-op equivalent).
        try doc.applyEdit(key: id, draft: p1.text, tracking: true)
        let after2 = try XCTUnwrap(doc.rows.first { $0.id == id }?.target)
        XCTAssertEqual(after1, after2)
        XCTAssertEqual(after2.components(separatedBy: "测试一下效果").count - 1, 1)
    }
}
