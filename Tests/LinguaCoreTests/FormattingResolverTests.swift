import XCTest
@testable import LinguaCore
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// FormattingResolver: tag-defs + fmt-defs → TextFormat (display-only, read-only).
final class FormattingResolverTests: XCTestCase {

    private func fixtureURL() -> URL {
        if let url = Bundle.module.url(forResource: "formatting", withExtension: "sdlxliff") {
            return url
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // LinguaCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // root
            .appendingPathComponent("Fixtures/formatting.sdlxliff")
    }

    private func loadXML() throws -> XMLDocument {
        let data = try Data(contentsOf: fixtureURL())
        return try XMLDocument(data: data, options: [.nodePreserveAll])
    }

    func testFmtDefsResolvedPerTag() throws {
        let resolver = FormattingResolver(document: try loadXML())
        XCTAssertEqual(resolver.fileFormats.count, 1)

        XCTAssertEqual(resolver.format(forTagID: "pt1")?.bold, true)
        XCTAssertEqual(resolver.format(forTagID: "pt2")?.italic, true)
        XCTAssertEqual(resolver.format(forTagID: "pt3")?.underline, true)
        XCTAssertEqual(resolver.format(forTagID: "pt4")?.position, .superscript)
        XCTAssertEqual(resolver.format(forTagID: "pt6")?.position, .subscript)
        XCTAssertEqual(resolver.format(forTagID: "pt5")?.textColor?.hex, "#FF0000")
        XCTAssertEqual(resolver.format(forTagID: "pt9")?.strikethrough, true)

        let pt7 = try XCTUnwrap(resolver.format(forTagID: "pt7"))
        XCTAssertEqual(pt7.bold, false)
        XCTAssertEqual(pt7.backgroundColor?.hex, "#FFFF00")
        XCTAssertEqual(pt7.fontName, "Times New Roman")
        XCTAssertEqual(pt7.fontSize, 10.5)

        // Non-formatting tags produce no entry.
        XCTAssertNil(resolver.format(forTagID: "pt10"))
        XCTAssertNil(resolver.format(forTagID: "ph11"))
    }

    func testBptOriginalTextFallbackWithoutFmtDef() throws {
        let resolver = FormattingResolver(document: try loadXML())
        let pt8 = try XCTUnwrap(resolver.format(forTagID: "pt8"))
        XCTAssertTrue(pt8.isBold)
        XCTAssertTrue(pt8.isItalic)
    }

    func testNestedFormatsCombineInnerWins() throws {
        let doc = try loadXML()
        let resolver = FormattingResolver(document: doc)
        let root = try XCTUnwrap(doc.rootElement())
        let target = try XCTUnwrap(
            elementsBelow(root).first { el in
                xmlLocalName(el) == "mrk"
                    && FormattingResolver.attr(el, "mid") == "3"
                    && (el.parent as? XMLElement).map(xmlLocalName) == "target"
            }
        )
        // <g pt1(bold)><g pt2(italic)><g pt7(bold=false, yellow bg)>…
        let gs = elementsBelow(target).filter { xmlLocalName($0) == "g" }
        XCTAssertEqual(gs.count, 3)
        var stack: [TextFormat] = []
        var combined: [TextFormat] = []
        for g in gs {
            stack.append(try XCTUnwrap(resolver.format(for: g)))
            combined.append(TextFormat.combined(stack))
        }
        XCTAssertTrue(combined[0].isBold && !combined[0].isItalic)
        XCTAssertTrue(combined[1].isBold && combined[1].isItalic)
        XCTAssertFalse(combined[2].isBold, "inner Bold=False switches bold off")
        XCTAssertTrue(combined[2].isItalic, "italic inherited from outer")
        XCTAssertEqual(combined[2].backgroundColor?.hex, "#FFFF00")
    }

    func testBxResolvesLikeG() throws {
        let doc = try loadXML()
        let resolver = FormattingResolver(document: doc)
        let bx = try XCTUnwrap(elementsBelow(try XCTUnwrap(doc.rootElement())).first { xmlLocalName($0) == "bx" })
        XCTAssertEqual(resolver.format(for: bx)?.bold, true)
        let ex = try XCTUnwrap(elementsBelow(try XCTUnwrap(doc.rootElement())).first { xmlLocalName($0) == "ex" })
        XCTAssertNil(resolver.format(for: ex))
    }

    func testValueParsers() {
        XCTAssertEqual(FormatValueParser.color("0xFF0000")?.hex, "#FF0000")
        XCTAssertEqual(FormatValueParser.color("#00ff00")?.hex, "#00FF00")
        XCTAssertEqual(FormatValueParser.color("0xFF0000FF")?.hex, "#0000FF") // AARRGGBB
        XCTAssertEqual(FormatValueParser.color("255, 0, 128")?.hex, "#FF0080")
        XCTAssertEqual(FormatValueParser.color("darkBlue")?.hex, "#00008B")
        XCTAssertEqual(FormatValueParser.color("Black")?.hex, "#000000")
        XCTAssertNil(FormatValueParser.color("Automatic"))
        XCTAssertNil(FormatValueParser.color("nonsense"))
        XCTAssertEqual(FormatValueParser.position("Superscript"), .superscript)
        XCTAssertEqual(FormatValueParser.position("Subscript"), .subscript)
        XCTAssertEqual(FormatValueParser.size("10.5pt"), 10.5)
        XCTAssertEqual(FormatValueParser.underline("Double"), true)
        XCTAssertEqual(FormatValueParser.underline("None"), false)

        let span = OriginalTagParser.format(
            fromOriginalTag: "<span style=\"font-weight:bold; text-decoration: underline; color:#00ff00\">"
        )
        XCTAssertTrue(span.isBold)
        XCTAssertTrue(span.isUnderline)
        XCTAssertEqual(span.textColor?.hex, "#00FF00")
        XCTAssertTrue(OriginalTagParser.format(fromOriginalTag: "<sup>").isSuperscript)
    }

    func testResolverDoesNotMutateDocument() throws {
        let doc = try loadXML()
        let before = doc.xmlData(options: [.nodePreserveAll])
        _ = FormattingResolver(document: doc)
        let after = doc.xmlData(options: [.nodePreserveAll])
        XCTAssertEqual(before, after)
    }

    #if os(macOS)
    /// Full core round-trip (macOS: WhitespacePreservingParser relies on Apple's XML parser).
    func testEditInsideFormattedRunKeepsTagsAndHeader() throws {
        let data = try Data(contentsOf: fixtureURL())
        let doc = try SDLXLIFFDocument(data: data, authorName: "UnitTest")
        let unedited = try doc.serializedData()
        _ = FormattingResolver(document: doc.xmlDocument)
        XCTAssertEqual(try doc.serializedData(), unedited, "building the resolver must not change output bytes")
        let headerBefore = try headerXML(doc)

        let key = SegmentKey(unitId: "f1", mid: "1")
        let plan = try XCTUnwrap(doc.plan(for: key))
        try doc.applyEdit(
            key: key,
            draft: plan.text.replacingOccurrences(of: "粗体", with: "加粗"),
            tracking: false
        )
        let saved = try XCTUnwrap(String(data: try doc.serializedData(), encoding: .utf8))
        XCTAssertTrue(saved.contains("<g id=\"pt1\">加粗</g>"))
        XCTAssertTrue(saved.contains("<fmt-def id=\"7\">"))
        XCTAssertTrue(saved.contains("&lt;cf bold=True&gt;"))

        XCTAssertEqual(try headerXML(doc), headerBefore, "fmt-defs / tag-defs untouched by edits")
        _ = data

        let reloaded = FormattingResolver(document: doc.xmlDocument)
        XCTAssertEqual(reloaded.format(forTagID: "pt1")?.bold, true)
    }

    private func headerXML(_ doc: SDLXLIFFDocument) throws -> String {
        let root = try XCTUnwrap(doc.xmlDocument.rootElement())
        let header = try XCTUnwrap(elementsBelow(root).first { xmlLocalName($0) == "header" })
        return header.xmlString(options: [.nodePreserveAll])
    }
    #endif
}
