import XCTest
@testable import LinguaCore
import Foundation

/// Round-trip safety tests for SDLXLIFF surgical edits (Mac / swift test).
final class RoundTripTests: XCTestCase {

    private func fixtureURL() -> URL {
        // Prefer SPM resource copy; fall back to repo Fixtures path.
        if let url = Bundle.module.url(forResource: "sample", withExtension: "sdlxliff") {
            return url
        }
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // LinguaCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // root
            .appendingPathComponent("Fixtures/sample.sdlxliff")
        return here
    }

    private func loadFixture() throws -> SDLXLIFFDocument {
        let data = try Data(contentsOf: fixtureURL())
        return try SDLXLIFFDocument(data: data, authorName: "UnitTest")
    }

    func testFixtureLoadsSegmentsAndNamespaces() throws {
        let doc = try loadFixture()
        XCTAssertGreaterThanOrEqual(doc.rows.count, 3)

        let root = try XCTUnwrap(doc.xmlDocument.rootElement())
        let ns = root.namespaces ?? []
        let uriValues = ns.compactMap(\.stringValue)
        XCTAssertTrue(uriValues.contains(SDLNamespaces.xliff) || root.uri == SDLNamespaces.xliff)
        // sdl prefix should resolve
        XCTAssertNotNil(root.resolveNamespace(forName: "sdl:revid") ?? root.namespace(forPrefix: "sdl"))

        let keys = Set(doc.rows.map(\.id))
        XCTAssertTrue(keys.contains(SegmentKey(unitId: "tu1", mid: "1")))
        XCTAssertTrue(keys.contains(SegmentKey(unitId: "tu2", mid: "2")))
    }

    func testLockedAndUntranslatableRespected() throws {
        let doc = try loadFixture()
        let locked = try XCTUnwrap(doc.rows.first { $0.id.mid == "2" })
        XCTAssertTrue(locked.isLocked)

        let untrans = try XCTUnwrap(doc.rows.first { $0.id.mid == "4" })
        XCTAssertTrue(untrans.isUntranslatable)

        XCTAssertThrowsError(
            try doc.applyEdit(
                key: locked.id,
                draft: (doc.plan(for: locked.id)?.text ?? "") + "x",
                tracking: false
            )
        )
    }

    func testPendingRevisionsDetected() throws {
        let doc = try loadFixture()
        let row = try XCTUnwrap(doc.rows.first { $0.id.mid == "3" })
        XCTAssertTrue(row.hasPendingRevisions)
    }

    func testEditPlainTextPreservesMidsAndTags() throws {
        let doc = try loadFixture()
        let key = SegmentKey(unitId: "tu1", mid: "1")
        let plan = try XCTUnwrap(doc.plan(for: key))

        // Replace only plain-text gaps; keep every token intact.
        var parts = try plan.split(plan.text)
        // gaps[0] is before first tag — "你好 "
        XCTAssertFalse(parts.isEmpty)
        parts[0] = "您好 "
        // Rebuild edited string
        var edited = parts[0]
        for i in plan.tokens.indices {
            edited += plan.tokens[i] + parts[i + 1]
        }

        let beforeTagCount = countTags(in: plan.root)
        try doc.applyEdit(key: key, draft: edited, tracking: false)

        let afterPlan = try XCTUnwrap(doc.plan(for: key))
        XCTAssertEqual(countTags(in: afterPlan.root), beforeTagCount)
        XCTAssertTrue(doc.rows.first { $0.id == key }?.target.contains("您好") == true)

        // Serialize and reload
        let data = try doc.serializedData()
        let reloaded = try SDLXLIFFDocument(data: data, authorName: "UnitTest")

        XCTAssertEqual(reloaded.rows.count, doc.rows.count)
        let reKey = SegmentKey(unitId: "tu1", mid: "1")
        XCTAssertNotNil(reloaded.targetNodes[reKey])
        XCTAssertEqual(
            reloaded.targetNodes[reKey]?.attribute(forName: "mid")?.stringValue,
            "1"
        )
        XCTAssertEqual(countTags(in: try XCTUnwrap(reloaded.targetNodes[reKey])), beforeTagCount)

        // Locked segment untouched
        let lockedTarget = try XCTUnwrap(reloaded.targetNodes[SegmentKey(unitId: "tu2", mid: "2")])
        XCTAssertTrue(visibleText(lockedTarget).contains("已锁定"))

        // Namespaces still present
        let root = try XCTUnwrap(reloaded.xmlDocument.rootElement())
        XCTAssertNotNil(root.namespace(forPrefix: "sdl") ?? root.resolveNamespace(forName: "sdl:revid"))

        // Inline g tag still present with same id
        let gTags = elementsBelow(try XCTUnwrap(reloaded.targetNodes[reKey])).filter {
            xmlLocalName($0) == "g"
        }
        XCTAssertEqual(gTags.count, 1)
        XCTAssertEqual(gTags[0].attribute(forName: "id")?.stringValue, "1")
    }

    func testStableSegmentKeysAcrossReload() throws {
        let doc = try loadFixture()
        let keysBefore = doc.rows.map(\.id)
        let data = try doc.serializedData()
        let reloaded = try SDLXLIFFDocument(data: data, authorName: "UnitTest")
        XCTAssertEqual(reloaded.rows.map(\.id), keysBefore)
    }

    func testAcceptRejectRevisions() throws {
        let doc = try loadFixture()
        let key = SegmentKey(unitId: "tu3", mid: "3")
        XCTAssertTrue(RevisionFactory.hasPending(in: try XCTUnwrap(doc.targetNodes[key])))

        try doc.resolveRevisions(key: key, accept: true)
        XCTAssertFalse(RevisionFactory.hasPending(in: try XCTUnwrap(doc.targetNodes[key])))
        let text = visibleText(try XCTUnwrap(doc.targetNodes[key]))
        XCTAssertTrue(text.contains("样例"))
        XCTAssertFalse(text.contains("示例"))
    }

    private func countTags(in root: XMLElement) -> Int {
        elementsBelow(root).filter {
            let name = xmlLocalName($0)
            return name == "g" || name == "x" || name == "bx" || name == "ex" || name == "ph"
        }.count
    }
}
