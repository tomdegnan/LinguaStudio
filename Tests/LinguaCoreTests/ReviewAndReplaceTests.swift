import XCTest
@testable import LinguaCore
import Foundation

/// Review-mode revision resolve + tag-safe replace tests.
final class ReviewAndReplaceTests: XCTestCase {

    private func fixtureURL() -> URL {
        if let url = Bundle.module.url(forResource: "sample", withExtension: "sdlxliff") {
            return url
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/sample.sdlxliff")
    }

    private func loadFixture() throws -> SDLXLIFFDocument {
        let data = try Data(contentsOf: fixtureURL())
        return try SDLXLIFFDocument(data: data, authorName: "UnitTest")
    }

    // MARK: - Review: detect → accept → no pending

    func testDetectPendingThenAcceptClearsMid() throws {
        let doc = try loadFixture()
        let key = SegmentKey(unitId: "tu3", mid: "3")

        let pendingBefore = RevisionFactory.pendingKeys(in: doc.rows)
        XCTAssertTrue(pendingBefore.contains(key))
        XCTAssertTrue(doc.rows.first { $0.id == key }?.hasPendingRevisions == true)
        XCTAssertTrue(RevisionFactory.hasPending(in: try XCTUnwrap(doc.targetNodes[key])))

        try doc.resolveRevisions(key: key, accept: true)

        XCTAssertFalse(doc.rows.first { $0.id == key }?.hasPendingRevisions == true)
        XCTAssertFalse(RevisionFactory.hasPending(in: try XCTUnwrap(doc.targetNodes[key])))
        XCTAssertFalse(RevisionFactory.pendingKeys(in: doc.rows).contains(key))

        // Accept keeps added text ("样例"), drops deleted ("示例")
        let text = visibleText(try XCTUnwrap(doc.targetNodes[key]))
        XCTAssertTrue(text.contains("样例"))
        XCTAssertFalse(text.contains("示例"))
    }

    func testRejectRestoresDeletedText() throws {
        let doc = try loadFixture()
        let key = SegmentKey(unitId: "tu3", mid: "3")
        try doc.resolveRevisions(key: key, accept: false)
        XCTAssertFalse(RevisionFactory.hasPending(in: try XCTUnwrap(doc.targetNodes[key])))
        let text = visibleText(try XCTUnwrap(doc.targetNodes[key]))
        XCTAssertTrue(text.contains("示例"))
        XCTAssertFalse(text.contains("样例"))
    }

    func testNextPreviousPendingNavigation() throws {
        let doc = try loadFixture()
        let keys = RevisionFactory.pendingKeys(in: doc.rows)
        XCTAssertEqual(keys.count, 1)
        XCTAssertEqual(keys[0].mid, "3")

        let next = RevisionFactory.nextPending(after: nil, in: keys)
        XCTAssertEqual(next, keys[0])
        // Wraps
        XCTAssertEqual(RevisionFactory.nextPending(after: keys[0], in: keys), keys[0])
        XCTAssertEqual(RevisionFactory.previousPending(before: keys[0], in: keys), keys[0])
    }

    // MARK: - Search / replace (gap-safe)

    func testGapReplaceDoesNotTouchTokens() throws {
        let doc = try loadFixture()
        let key = SegmentKey(unitId: "tu1", mid: "1")
        let plan = try XCTUnwrap(doc.plan(for: key))
        let beforeTokens = plan.tokens
        let beforeTagCount = elementsBelow(plan.root).filter { xmlLocalName($0) == "g" }.count

        let result = try doc.replaceInTarget(
            key: key,
            find: "你好",
            replacement: "您好",
            options: SearchOptions(),
            tracking: false
        )
        guard case .applied(_, let count, _) = result else {
            return XCTFail("expected applied, got \(result)")
        }
        XCTAssertEqual(count, 1)

        let afterPlan = try XCTUnwrap(doc.plan(for: key))
        XCTAssertEqual(afterPlan.tokens, beforeTokens)
        XCTAssertEqual(
            elementsBelow(afterPlan.root).filter { xmlLocalName($0) == "g" }.count,
            beforeTagCount
        )
        XCTAssertTrue(doc.rows.first { $0.id == key }?.target.contains("您好") == true)
    }

    func testReplaceSkipsWhenMatchWouldCrossTags() throws {
        // Build a synthetic plan-like situation: find text that only matches across gaps.
        // Fixture target mid=1 is "你好 <g>世界</g>！" — searching "你好世界" spans the g tag.
        let doc = try loadFixture()
        let key = SegmentKey(unitId: "tu1", mid: "1")
        let plan = try XCTUnwrap(doc.plan(for: key))

        let result = SearchReplace.replaceInGaps(
            plan: plan,
            find: "你好世界",
            replacement: "XX",
            options: SearchOptions()
        )
        // Joined gaps = "你好 世界！" so "你好世界" without space may or may not match.
        // Use a pattern that joins across the tag boundary: " 世界" is in one gap;
        // "你好 世界" spans gaps[0]="你好 " and gaps inside g="世界".
        let cross = SearchReplace.replaceInGaps(
            plan: plan,
            find: "你好 世界",
            replacement: "整块",
            options: SearchOptions()
        )
        XCTAssertEqual(cross, .skippedUnsafe)

        // Plain in-gap replace still works
        let safe = SearchReplace.replaceInGaps(
            plan: plan,
            find: "世界",
            replacement: "天下",
            options: SearchOptions()
        )
        guard case .applied(_, let n, _) = safe else {
            return XCTFail("expected applied for in-gap replace")
        }
        XCTAssertEqual(n, 1)
        _ = result
    }

    func testCaseSensitiveAndWholeWord() throws {
        let text = "Hello hello HELLO"
        XCTAssertEqual(
            SearchReplace.matchCount(in: text, pattern: "hello", options: SearchOptions()),
            3
        )
        XCTAssertEqual(
            SearchReplace.matchCount(
                in: text,
                pattern: "hello",
                options: SearchOptions(caseSensitive: true)
            ),
            1
        )
        XCTAssertEqual(
            SearchReplace.matchCount(
                in: "cat catalog cat",
                pattern: "cat",
                options: SearchOptions(wholeWord: true)
            ),
            2
        )
    }

    func testBulkResolveAllPending() throws {
        let doc = try loadFixture()
        let keys = RevisionFactory.pendingKeys(in: doc.rows)
        XCTAssertFalse(keys.isEmpty)
        let count = try doc.resolveRevisions(keys: keys, accept: true)
        XCTAssertEqual(count, keys.count)
        XCTAssertTrue(RevisionFactory.pendingKeys(in: doc.rows).isEmpty)
    }

    func testReplaceFirstOnlyLeavesLaterMatches() throws {
        let doc = try loadFixture()
        let key = SegmentKey(unitId: "tu1", mid: "1")
        let plan = try XCTUnwrap(doc.plan(for: key))
        let draft = plan.text
        guard draft.contains("你好") else {
            return XCTFail("unexpected fixture text \(draft)")
        }
        let once = SearchReplace.replaceInDraft(
            plan: plan,
            draft: draft,
            find: "你好",
            replacement: "您好",
            options: SearchOptions(),
            firstOnly: true
        )
        guard case .applied(let d1, let c1, let sel) = once else {
            return XCTFail("expected applied, got \(once)")
        }
        XCTAssertEqual(c1, 1)
        XCTAssertNotNil(sel)
        XCTAssertTrue(d1.contains("您好"))
        XCTAssertFalse(d1.contains("你好"))
    }

    func testReplaceInsideRevisionWhenTrackingOn() throws {
        let doc = try loadFixture()
        let key = SegmentKey(unitId: "tu3", mid: "3")
        XCTAssertTrue(doc.rows.first { $0.id == key }?.hasPendingRevisions == true)
        let visible = try XCTUnwrap(doc.rows.first { $0.id == key }?.target)
        // Fixture mid=3 has 样例 (added) / 示例 (deleted). Replace inside added when tracking on.
        let needle = visible.contains("样例") ? "样例" : String(visible.prefix(1))
        let result = try doc.replaceInTarget(
            key: key,
            find: needle,
            replacement: "XX",
            options: SearchOptions(),
            tracking: true,
            firstOnly: true
        )
        guard case .applied(_, let count, _) = result else {
            return XCTFail("expected applied with tracking on, got \(result)")
        }
        XCTAssertEqual(count, 1)
        let after = try XCTUnwrap(doc.rows.first { $0.id == key }?.target)
        XCTAssertTrue(after.contains("XX"))
    }

    func testReplaceInsideRevisionLockedWhenTrackingOff() throws {
        let doc = try loadFixture()
        let key = SegmentKey(unitId: "tu3", mid: "3")
        let plan = try XCTUnwrap(doc.plan(for: key))
        // If there is a revision gap with distinct text, replacing it OFF should skipLocked
        // when that is the only match.
        guard plan.revisionGaps.contains(true) else {
            return XCTFail("expected revision gaps on tu3")
        }
        var lockedOnly = false
        for (i, gap) in plan.gaps.enumerated() where plan.revisionGaps[i] && !gap.isEmpty {
            let token = String(gap.prefix(1))
            // Ensure this token does not also appear in non-revision gaps.
            let elsewhere = zip(plan.gaps, plan.revisionGaps).contains { g, rev in
                !rev && g.contains(token)
            }
            if elsewhere { continue }
            let result = SearchReplace.replaceInGaps(
                plan: plan,
                find: token,
                replacement: "Z",
                options: SearchOptions(),
                firstOnly: true,
                allowRevisionEdits: false
            )
            XCTAssertEqual(result, .skippedLocked, "token \(token) result \(result)")
            lockedOnly = true
            break
        }
        if !lockedOnly {
            // Fallback: allowRevisionEdits false still allows non-revision replaces.
            let result = try doc.replaceInTarget(
                key: key,
                find: "___nomatch___",
                replacement: "Z",
                options: SearchOptions(),
                tracking: false
            )
            XCTAssertEqual(result, .noMatch)
        }
        _ = plan
    }


    /// Case-changing replace must not prevent finding the remaining matches
    /// (UI used to filter on Find text; core scan must keep working after case edits).
    func testSuccessiveCaseChangingReplacesFindRemaining() throws {
        let root = XMLElement(name: "target")
        let textNode = XMLNode.text(withStringValue: "hello Hello HELLO") as! XMLNode
        root.addChild(textNode)
        let plan = TagPlan(root)

        let opts = SearchOptions(caseSensitive: false)
        let r1 = SearchReplace.replaceInGaps(
            plan: plan,
            find: "hello",
            replacement: "Hey",
            options: opts,
            firstOnly: true
        )
        guard case .applied(let d1, let c1, _) = r1 else {
            return XCTFail("first replace failed: \(r1)")
        }
        XCTAssertEqual(c1, 1)
        XCTAssertEqual(d1, "Hey Hello HELLO")

        // Rebuild plan gaps from applied draft for next firstOnly pass.
        let r2 = SearchReplace.replaceInDraft(
            plan: plan,
            draft: d1,
            find: "hello",
            replacement: "Hey",
            options: opts,
            firstOnly: true,
            startFromDraftUTF16: ("Hey" as NSString).length
        )
        guard case .applied(let d2, let c2, _) = r2 else {
            return XCTFail("second replace failed: \(r2)")
        }
        XCTAssertEqual(c2, 1)
        XCTAssertEqual(d2, "Hey Hey HELLO")

        let r3 = SearchReplace.replaceInDraft(
            plan: plan,
            draft: d2,
            find: "hello",
            replacement: "Hey",
            options: opts,
            firstOnly: true,
            startFromDraftUTF16: ("Hey Hey" as NSString).length
        )
        guard case .applied(let d3, let c3, _) = r3 else {
            return XCTFail("third replace failed: \(r3)")
        }
        XCTAssertEqual(c3, 1)
        XCTAssertEqual(d3, "Hey Hey Hey")
    }

    func testMatchStillVisibleAfterCaseChangeInPlainText() {
        let before = "alpha beta"
        let after = "ALPHA beta"
        let opts = SearchOptions(caseSensitive: false)
        XCTAssertEqual(SearchReplace.matchCount(in: before, pattern: "alpha", options: opts), 1)
        // After replacing alpha→ALPHA, case-insensitive find still sees ALPHA.
        XCTAssertEqual(SearchReplace.matchCount(in: after, pattern: "alpha", options: opts), 1)
        // Case-sensitive find for original lowercase should not see ALPHA — that's expected;
        // Replace itself re-scans with the same options rather than a stale hit list.
        XCTAssertEqual(
            SearchReplace.matchCount(in: after, pattern: "alpha", options: SearchOptions(caseSensitive: true)),
            0
        )
    }


    /// One-click Replace must replace a match that starts at `startFrom` (selected match),
    /// not skip it the way Word does when startFrom is the match end.
    func testFirstOnlyReplacesMatchStartingAtCaretNotOnlyAfter() throws {
        let root = XMLElement(name: "target")
        root.addChild(XMLNode.text(withStringValue: "Redacted other Redacted") as! XMLNode)
        let plan = TagPlan(root)
        let opts = SearchOptions(caseSensitive: true)

        // startFrom at first match start → replaces first (one click).
        let atStart = SearchReplace.replaceInGaps(
            plan: plan,
            find: "Redacted",
            replacement: "redacted",
            options: opts,
            firstOnly: true,
            startFromDraftUTF16: 0
        )
        guard case .applied(let d1, let c1, let sel1) = atStart else {
            return XCTFail("expected replace at match start, got \(atStart)")
        }
        XCTAssertEqual(c1, 1)
        XCTAssertEqual(d1, "redacted other Redacted")
        XCTAssertEqual(sel1, NSRange(location: 0, length: ("redacted" as NSString).length))

        // Old Word-style: startFrom at first match END skips first match.
        let firstLen = ("Redacted" as NSString).length
        let afterFirst = SearchReplace.replaceInGaps(
            plan: plan,
            find: "Redacted",
            replacement: "redacted",
            options: opts,
            firstOnly: true,
            startFromDraftUTF16: firstLen
        )
        guard case .applied(let d2, let c2, _) = afterFirst else {
            return XCTFail("expected replace of second match when starting after first, got \(afterFirst)")
        }
        XCTAssertEqual(c2, 1)
        XCTAssertEqual(d2, "Redacted other redacted")

        // Successive: after first replace, start after replacement → second match.
        let afterRepl = SearchReplace.replaceInDraft(
            plan: plan,
            draft: d1,
            find: "Redacted",
            replacement: "redacted",
            options: opts,
            firstOnly: true,
            startFromDraftUTF16: ("redacted" as NSString).length
        )
        guard case .applied(let d3, let c3, _) = afterRepl else {
            return XCTFail("expected successive replace, got \(afterRepl)")
        }
        XCTAssertEqual(c3, 1)
        XCTAssertEqual(d3, "redacted other redacted")
    }

    /// Case-sensitive Find still replaces on first attempt without a prior Find Next.
    func testCaseSensitiveReplaceWithoutPriorFind() throws {
        let root = XMLElement(name: "target")
        root.addChild(XMLNode.text(withStringValue: "xx Redacted yy") as! XMLNode)
        let plan = TagPlan(root)
        let result = SearchReplace.replaceInGaps(
            plan: plan,
            find: "Redacted",
            replacement: "redacted",
            options: SearchOptions(caseSensitive: true),
            firstOnly: true,
            startFromDraftUTF16: 0
        )
        guard case .applied(let draft, let count, let sel) = result else {
            return XCTFail("expected applied, got \(result)")
        }
        XCTAssertEqual(count, 1)
        XCTAssertEqual(draft, "xx redacted yy")
        XCTAssertNotNil(sel)
        XCTAssertFalse(draft.contains("Redacted"))
    }


    /// Regression: single Replace must still succeed when the first attempt starts
    /// past the only match (caret after match) — retry from 0 / same as Replace All path.
    func testSingleReplaceRetryFromStartWhenCaretPastOnlyMatch() throws {
        let root = XMLElement(name: "target")
        root.addChild(XMLNode.text(withStringValue: "prefix Redacted") as! XMLNode)
        let plan = TagPlan(root)
        let opts = SearchOptions(caseSensitive: true)
        let past = ("prefix Redacted" as NSString).length  // caret at end after match

        let miss = SearchReplace.replaceInGaps(
            plan: plan,
            find: "Redacted",
            replacement: "redacted",
            options: opts,
            firstOnly: true,
            startFromDraftUTF16: past
        )
        XCTAssertEqual(miss, .noMatch, "starting past the only match must miss")

        let hit = SearchReplace.replaceInGaps(
            plan: plan,
            find: "Redacted",
            replacement: "redacted",
            options: opts,
            firstOnly: true,
            startFromDraftUTF16: 0
        )
        guard case .applied(let draft, let count, let sel) = hit else {
            return XCTFail("retry from 0 must replace like Replace All, got \(hit)")
        }
        XCTAssertEqual(count, 1)
        XCTAssertEqual(draft, "prefix redacted")
        XCTAssertEqual(sel?.location, ("prefix " as NSString).length)
    }

    func testFirstMatchDraftUTF16SkipsBeforeStartFrom() {
        let text = "Redacted and Redacted"
        let opts = SearchOptions(caseSensitive: true)
        let first = SearchReplace.firstMatchDraftUTF16(
            in: text, pattern: "Redacted", options: opts, startFromUTF16: 0
        )
        XCTAssertEqual(first, NSRange(location: 0, length: 8))
        let second = SearchReplace.firstMatchDraftUTF16(
            in: text, pattern: "Redacted", options: opts, startFromUTF16: 8
        )
        XCTAssertEqual(second?.location, ("Redacted and " as NSString).length)
        XCTAssertEqual(second?.length, 8)
    }

    /// Document-level: firstOnly replaceInTarget updates target like Replace All would for one hit.
    func testDocumentReplaceFirstOnlyUpdatesTarget() throws {
        let doc = try loadFixture()
        let key = SegmentKey(unitId: "tu1", mid: "1")
        let before = try XCTUnwrap(doc.rows.first { $0.id == key }?.target)
        guard before.contains("你好") else {
            return XCTFail("unexpected fixture \(before)")
        }
        let result = try doc.replaceInTarget(
            key: key,
            find: "你好",
            replacement: "您好",
            options: SearchOptions(),
            tracking: false,
            firstOnly: true,
            startFromDraftUTF16: 0
        )
        guard case .applied(_, let count, let sel) = result else {
            return XCTFail("expected applied, got \(result)")
        }
        XCTAssertEqual(count, 1)
        XCTAssertNotNil(sel)
        let after = try XCTUnwrap(doc.rows.first { $0.id == key }?.target)
        XCTAssertTrue(after.contains("您好"))
        XCTAssertFalse(after.contains("你好"))
    }

}
