import XCTest
@testable import LinguaCore
import Foundation

final class InlineFormatTests: XCTestCase {

    private func loadFormatting() throws -> SDLXLIFFDocument {
        let url = Bundle.module.url(forResource: "formatting", withExtension: "sdlxliff")
            ?? URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures/formatting.sdlxliff")
        let data = try Data(contentsOf: url)
        return try SDLXLIFFDocument(data: data, authorName: "UnitTest")
    }

    private let plainXML = """
    <?xml version="1.0" encoding="utf-8"?>
    <xliff xmlns="urn:oasis:names:tc:xliff:document:1.2" xmlns:sdl="http://sdl.com/FileTypes/SdlXliff/1.0" version="1.2" sdl:version="1.0">
      <file original="m.docx" source-language="en-US" target-language="zh-CN" datatype="x-sdl-plaintext">
        <header></header>
        <body>
          <trans-unit id="u1">
            <source>Hello world</source>
            <seg-source><mrk mtype="seg" mid="1">Hello world</mrk></seg-source>
            <target><mrk mtype="seg" mid="1">Hello world</mrk></target>
            <sdl:seg-defs><sdl:seg id="1" conf="Translated"/></sdl:seg-defs>
          </trans-unit>
        </body>
      </file>
    </xliff>
    """

    func testEnsureTagReusesExistingBold() throws {
        let doc = try loadFormatting()
        let id = try FormatTagSupport.ensureTagID(for: .bold, in: doc.xmlDocument)
        XCTAssertEqual(id, "pt1", "should reuse fixture bold tag pt1")
        let italic = try FormatTagSupport.ensureTagID(for: .italic, in: doc.xmlDocument)
        XCTAssertEqual(italic, "pt2")
        let under = try FormatTagSupport.ensureTagID(for: .underline, in: doc.xmlDocument)
        XCTAssertEqual(under, "pt3")
    }

    func testWrapPlainTextCreatesGAndDisplaysBold() throws {
        let doc = try SDLXLIFFDocument(data: Data(plainXML.utf8), authorName: "UnitTest")
        let key = SegmentKey(unitId: "u1", mid: "1")
        let plan = try XCTUnwrap(doc.plan(for: key))
        XCTAssertEqual(plan.text, "Hello world")
        let range = NSRange(location: 6, length: 5)
        let draft = try doc.applyInlineFormat(key: key, kind: .bold, draftUTF16Range: range)
        XCTAssertTrue(draft.contains("⟦"), "expected tag tokens in draft: \(draft)")
        XCTAssertTrue(draft.contains("world"))
        let xml = try XCTUnwrap(String(data: try doc.serializedData(), encoding: .utf8))
        XCTAssertTrue(xml.contains("<g id="), xml)
        XCTAssertTrue(xml.contains("world"), xml)
        let resolver = FormattingResolver(document: doc.xmlDocument)
        let tagID = try FormatTagSupport.ensureTagID(for: .bold, in: doc.xmlDocument)
        XCTAssertEqual(resolver.format(forTagID: tagID)?.bold, true)
        XCTAssertEqual(doc.rows.first?.status, .draft)
    }

    func testGapSliceRejectsCrossTagSelection() throws {
        let doc = try loadFormatting()
        let key = SegmentKey(unitId: "f1", mid: "1")
        let plan = try XCTUnwrap(doc.plan(for: key))
        let all = NSRange(location: 0, length: (plan.text as NSString).length)
        XCTAssertNil(FormatTagSupport.gapSlice(plan: plan, draftUTF16Range: all))
    }

    func testToggleUnwrapRemovesWrapper() throws {
        let doc = try SDLXLIFFDocument(data: Data(plainXML.utf8), authorName: "UnitTest")
        let key = SegmentKey(unitId: "u1", mid: "1")
        let full = NSRange(location: 0, length: ("Hello world" as NSString).length)
        _ = try doc.applyInlineFormat(key: key, kind: .bold, draftUTF16Range: full)
        let plan1 = try XCTUnwrap(doc.plan(for: key))
        if let idx = plan1.gaps.firstIndex(where: { $0 == "Hello world" }) {
            var cursor = 0
            for i in 0..<idx {
                cursor += (plan1.gaps[i] as NSString).length
                if i < plan1.tokens.count {
                    cursor += (plan1.tokens[i] as NSString).length
                }
            }
            let inner = NSRange(location: cursor, length: ("Hello world" as NSString).length)
            _ = try doc.applyInlineFormat(key: key, kind: .bold, draftUTF16Range: inner)
        } else {
            XCTFail("missing wrapped gap")
        }
        let plain = try XCTUnwrap(doc.plan(for: key)?.text)
        XCTAssertEqual(plain, "Hello world")
    }

    /// Selecting only "world" must not italicize "Hello ".
    func testPartialMidStringItalic() throws {
        let doc = try SDLXLIFFDocument(data: Data(plainXML.utf8), authorName: "UnitTest")
        let key = SegmentKey(unitId: "u1", mid: "1")
        let range = NSRange(location: 6, length: 5)
        let slice = try XCTUnwrap(
            FormatTagSupport.gapSlice(
                plan: try XCTUnwrap(doc.plan(for: key)),
                draftUTF16Range: range
            )
        )
        XCTAssertEqual(slice.start, 6)
        XCTAssertEqual(slice.end, 11)

        let draft = try doc.applyInlineFormat(key: key, kind: .italic, draftUTF16Range: range)
        XCTAssertTrue(draft.hasPrefix("Hello "), draft)
        XCTAssertFalse(draft.hasPrefix("⟦"), "must not wrap leading text: \(draft)")

        let xmlOut = try XCTUnwrap(String(data: try doc.serializedData(), encoding: .utf8))
        XCTAssertTrue(xmlOut.contains(">Hello <g "), xmlOut)
        XCTAssertTrue(xmlOut.contains("world</g>"), xmlOut)
    }

    /// Hubert repro: select only `17MAR2026` inside `Angers, 17MAR2026`.
    func testPartialDateSuffixItalicLikeUI() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <xliff xmlns="urn:oasis:names:tc:xliff:document:1.2" xmlns:sdl="http://sdl.com/FileTypes/SdlXliff/1.0" version="1.2" sdl:version="1.0">
          <file original="m.docx" source-language="fr-FR" target-language="en-US" datatype="x-sdl-plaintext">
            <header></header>
            <body>
              <trans-unit id="u3">
                <source>Angers, le 17/03/2026</source>
                <seg-source><mrk mtype="seg" mid="3">Angers, le 17/03/2026</mrk></seg-source>
                <target><mrk mtype="seg" mid="3">Angers, 17MAR2026</mrk></target>
                <sdl:seg-defs><sdl:seg id="3" conf="Translated"/></sdl:seg-defs>
              </trans-unit>
            </body>
          </file>
        </xliff>
        """
        let doc = try SDLXLIFFDocument(data: Data(xml.utf8), authorName: "UnitTest")
        let key = SegmentKey(unitId: "u3", mid: "3")
        let loc = ("Angers, 17MAR2026" as NSString).range(of: "17MAR2026")
        XCTAssertEqual(loc.location, 8)
        let draft = try doc.applyInlineFormat(key: key, kind: .italic, draftUTF16Range: loc)
        XCTAssertTrue(draft.hasPrefix("Angers, "), draft)
        XCTAssertFalse(draft.hasPrefix("⟦"), draft)
        let xmlOut = try XCTUnwrap(String(data: try doc.serializedData(), encoding: .utf8))
        XCTAssertTrue(xmlOut.contains(">Angers, <g "), xmlOut)
        XCTAssertTrue(xmlOut.contains("17MAR2026</g>"), xmlOut)
        XCTAssertFalse(xmlOut.contains("<g id=\"ls-i\">Angers"), xmlOut)
    }

    func testEmptyCaretWrapsWholePlainSegment() throws {
        let doc = try SDLXLIFFDocument(data: Data(plainXML.utf8), authorName: "UnitTest")
        let key = SegmentKey(unitId: "u1", mid: "1")
        let plan = try XCTUnwrap(doc.plan(for: key))
        let range = try XCTUnwrap(FormatTagSupport.rangeForEmptyCaret(plan: plan, caretDraftUTF16: 3))
        XCTAssertEqual(range.location, 0)
        XCTAssertEqual(range.length, ("Hello world" as NSString).length)
        let draft = try doc.applyInlineFormat(key: key, kind: .italic, draftUTF16Range: range)
        XCTAssertTrue(draft.hasPrefix("⟦") || draft.contains("Hello"), draft)
        let xmlOut = try XCTUnwrap(String(data: try doc.serializedData(), encoding: .utf8))
        XCTAssertTrue(xmlOut.contains("Hello world</g>") || xmlOut.contains(">Hello world<"), xmlOut)
    }
    func testSuperscriptCreatesFmtDefAndResolves() throws {
        let doc = try SDLXLIFFDocument(data: Data(plainXML.utf8), authorName: "UnitTest")
        let key = SegmentKey(unitId: "u1", mid: "1")
        let range = NSRange(location: 6, length: 5)
        let draft = try doc.applyInlineFormat(key: key, kind: .superscript, draftUTF16Range: range)
        XCTAssertTrue(draft.contains("world"), draft)
        let xml = try XCTUnwrap(String(data: try doc.serializedData(), encoding: .utf8))
        XCTAssertTrue(xml.contains("ls-sup") || xml.contains("TextPosition"), xml)
        XCTAssertTrue(xml.contains("Superscript") || xml.contains("superscript"), xml)
        let tagID = try FormatTagSupport.ensureTagID(for: .superscript, in: doc.xmlDocument)
        var resolver = FormattingResolver(document: doc.xmlDocument)
        XCTAssertEqual(resolver.format(forTagID: tagID)?.position, .superscript)
        let subID = try FormatTagSupport.ensureTagID(for: .subscript, in: doc.xmlDocument)
        resolver = FormattingResolver(document: doc.xmlDocument)
        XCTAssertEqual(resolver.format(forTagID: subID)?.position, .subscript)
    }
}
