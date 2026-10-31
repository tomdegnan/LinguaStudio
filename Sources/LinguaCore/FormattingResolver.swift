import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Vertical text position from SDL `TextPosition` (or `<sup>` / `<sub>` style tags).
public enum TextPosition: String, Hashable, Sendable {
    case normal
    case superscript
    case `subscript`
}

/// An sRGB colour parsed from SDL formatting values (components 0…1).
public struct RGBAColor: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `#RRGGBB` (alpha omitted).
    public var hex: String {
        func byte(_ v: Double) -> Int { Int((max(0, min(1, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    /// Relative luminance (rough, sRGB weights) — used by the UI to skip
    /// "Black"/"White" text colours that would vanish in dark/light mode.
    public var luminance: Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}

/// Display formatting for a run of text. `nil` means "inherit from the enclosing run";
/// an explicit `false` (e.g. `Bold=False`) switches an inherited value off.
public struct TextFormat: Hashable, Sendable {
    public var bold: Bool?
    public var italic: Bool?
    public var underline: Bool?
    public var strikethrough: Bool?
    public var position: TextPosition?
    public var textColor: RGBAColor?
    public var backgroundColor: RGBAColor?
    public var fontName: String?
    public var fontSize: Double?

    public init(
        bold: Bool? = nil,
        italic: Bool? = nil,
        underline: Bool? = nil,
        strikethrough: Bool? = nil,
        position: TextPosition? = nil,
        textColor: RGBAColor? = nil,
        backgroundColor: RGBAColor? = nil,
        fontName: String? = nil,
        fontSize: Double? = nil
    ) {
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.position = position
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.fontName = fontName
        self.fontSize = fontSize
    }

    public static let plain = TextFormat()

    public var isEmpty: Bool { self == TextFormat.plain }

    public var isBold: Bool { bold == true }
    public var isItalic: Bool { italic == true }
    public var isUnderline: Bool { underline == true }
    public var isStrikethrough: Bool { strikethrough == true }
    public var isSuperscript: Bool { position == .superscript }
    public var isSubscript: Bool { position == .subscript }

    /// Returns `inner` laid over `self`: every property `inner` sets wins,
    /// everything it leaves `nil` is inherited from `self` (the outer run).
    public func applying(_ inner: TextFormat) -> TextFormat {
        TextFormat(
            bold: inner.bold ?? bold,
            italic: inner.italic ?? italic,
            underline: inner.underline ?? underline,
            strikethrough: inner.strikethrough ?? strikethrough,
            position: inner.position ?? position,
            textColor: inner.textColor ?? textColor,
            backgroundColor: inner.backgroundColor ?? backgroundColor,
            fontName: inner.fontName ?? fontName,
            fontSize: inner.fontSize ?? fontSize
        )
    }

    /// Combine a list of formats from outermost to innermost.
    public static func combined<S: Sequence>(_ formats: S) -> TextFormat where S.Element == TextFormat {
        formats.reduce(TextFormat.plain) { $0.applying($1) }
    }

    /// Apply one SDL `<value key="…">…</value>` pair. Unknown keys are ignored.
    public mutating func apply(key rawKey: String, value rawValue: String) {
        let key = rawKey.lowercased().filter { !$0.isWhitespace && $0 != "_" && $0 != "-" }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch key {
        case "bold", "b", "fontweight":
            if key == "fontweight" {
                let lower = value.lowercased()
                if let weight = Double(lower) {
                    bold = weight >= 600
                } else {
                    bold = lower.contains("bold") || lower == "heavy" || lower == "black"
                }
            } else {
                bold = FormatValueParser.bool(value) ?? bold
            }
        case "italic", "i":
            italic = FormatValueParser.bool(value) ?? italic
        case "fontstyle":
            let lower = value.lowercased()
            italic = lower.contains("italic") || lower.contains("oblique")
        case "underline", "u", "underlinestyle":
            underline = FormatValueParser.underline(value) ?? underline
        case "strikethrough", "strike", "strikeout", "doublestrikethrough", "dstrike", "s":
            strikethrough = FormatValueParser.bool(value) ?? strikethrough
        case "textposition", "verticalalign", "position", "vertalign":
            position = FormatValueParser.position(value) ?? position
        case "superscript", "sup":
            if FormatValueParser.bool(value) == true { position = .superscript }
        case "subscript", "sub":
            if FormatValueParser.bool(value) == true { position = .subscript }
        case "textcolor", "color", "fontcolor", "forecolor", "foregroundcolor":
            if let colour = FormatValueParser.color(value) { textColor = colour }
        case "backgroundcolor", "background", "highlight", "highlightcolor", "backcolor", "shading":
            if let colour = FormatValueParser.color(value) { backgroundColor = colour }
        case "fontname", "font", "fontfamily", "face", "typeface":
            if !value.isEmpty { fontName = value }
        case "fontsize", "size":
            if let size = FormatValueParser.size(value) { fontSize = size }
        default:
            break
        }
    }
}

/// Tolerant parsers for the value strings Trados file types write.
public enum FormatValueParser {

    public static func bool(_ value: String) -> Bool? {
        switch value.trimmingCharacters(in: .whitespaces).lowercased() {
        case "true", "1", "yes", "on", "bold", "italic", "single": return true
        case "false", "0", "no", "off", "none", "normal": return false
        case "": return true // bare attribute like <cf bold>
        default: return nil
        }
    }

    /// Word writes underline as True/False or a style name (Single, Double, Words, Dotted…).
    public static func underline(_ value: String) -> Bool? {
        if let b = bool(value) { return b }
        return value.isEmpty ? nil : true
    }

    public static func position(_ value: String) -> TextPosition? {
        let lower = value.lowercased()
        if lower.hasPrefix("super") { return .superscript }
        if lower.hasPrefix("sub") { return .subscript }
        if ["normal", "baseline", "none", "false"].contains(lower) { return .normal }
        return nil
    }

    public static func size(_ value: String) -> Double? {
        let cleaned = value.lowercased()
            .replacingOccurrences(of: "pt", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let size = Double(cleaned), size > 0, size < 1000 else { return nil }
        return size
    }

    /// Accepts `0xRRGGBB`, `#RRGGBB`, `RRGGBB`, 8-digit `AARRGGBB`, `#RGB`,
    /// `R,G,B` / `A,R,G,B` decimal lists, `rgb(r,g,b)` and common .NET / Word colour names.
    /// Returns nil for "Automatic" / "Auto" / "Transparent" / "Empty" and unparseable values.
    public static func color(_ raw: String) -> RGBAColor? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let lower = value.lowercased()
        if ["auto", "automatic", "transparent", "empty", "none", "default", "windowtext"].contains(lower) {
            return nil
        }

        if lower.hasPrefix("rgb(") || lower.hasPrefix("rgba(") {
            value = String(value.drop(while: { $0 != "(" }).dropFirst().prefix(while: { $0 != ")" }))
            let parts = value.split(separator: ",").compactMap {
                Double($0.trimmingCharacters(in: .whitespaces))
            }
            guard parts.count >= 3 else { return nil }
            return RGBAColor(red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255)
        }

        if value.contains(",") {
            let parts = value.split(separator: ",").compactMap {
                Double($0.trimmingCharacters(in: .whitespaces))
            }
            if parts.count == 3 {
                return RGBAColor(red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255)
            }
            if parts.count == 4 {
                // .NET ColorConverter order: A, R, G, B
                let alpha = parts[0] == 0 ? 1 : parts[0] / 255
                return RGBAColor(red: parts[1] / 255, green: parts[2] / 255, blue: parts[3] / 255, alpha: alpha)
            }
            return nil
        }

        var hexDigits = lower
        if hexDigits.hasPrefix("0x") {
            hexDigits = String(hexDigits.dropFirst(2))
        } else if hexDigits.hasPrefix("#") {
            hexDigits = String(hexDigits.dropFirst())
        } else if hexDigits.hasPrefix("&h") {
            hexDigits = String(hexDigits.dropFirst(2))
        }
        let isHex = !hexDigits.isEmpty && hexDigits.allSatisfy { $0.isHexDigit }
        let looksHex = isHex && (lower.hasPrefix("0x") || lower.hasPrefix("#") || lower.hasPrefix("&h")
            || hexDigits.count == 6 || hexDigits.count == 8)
        if looksHex, let number = UInt64(hexDigits, radix: 16) {
            switch hexDigits.count {
            case 3:
                let r = Double((number >> 8) & 0xF) / 15
                let g = Double((number >> 4) & 0xF) / 15
                let b = Double(number & 0xF) / 15
                return RGBAColor(red: r, green: g, blue: b)
            case 6:
                return RGBAColor(
                    red: Double((number >> 16) & 0xFF) / 255,
                    green: Double((number >> 8) & 0xFF) / 255,
                    blue: Double(number & 0xFF) / 255
                )
            case 8:
                // .NET Color.ToArgb order: AARRGGBB. Alpha 0 is treated as opaque
                // (some writers leave the alpha byte empty).
                let a = Double((number >> 24) & 0xFF) / 255
                return RGBAColor(
                    red: Double((number >> 16) & 0xFF) / 255,
                    green: Double((number >> 8) & 0xFF) / 255,
                    blue: Double(number & 0xFF) / 255,
                    alpha: a == 0 ? 1 : a
                )
            default:
                return nil
            }
        }

        let name = lower.filter { $0.isLetter }
        if let rgb = namedColors[name] {
            return RGBAColor(red: Double(rgb.0) / 255, green: Double(rgb.1) / 255, blue: Double(rgb.2) / 255)
        }
        return nil
    }

    /// .NET KnownColor / Word highlight names commonly seen in SDLXLIFF (lowercased, letters only).
    static let namedColors: [String: (Int, Int, Int)] = [
        "black": (0, 0, 0),
        "white": (255, 255, 255),
        "red": (255, 0, 0),
        "green": (0, 128, 0),
        "lime": (0, 255, 0),
        "brightgreen": (0, 255, 0),
        "blue": (0, 0, 255),
        "yellow": (255, 255, 0),
        "cyan": (0, 255, 255),
        "aqua": (0, 255, 255),
        "turquoise": (64, 224, 208),
        "magenta": (255, 0, 255),
        "fuchsia": (255, 0, 255),
        "pink": (255, 192, 203),
        "gray": (128, 128, 128),
        "grey": (128, 128, 128),
        "silver": (192, 192, 192),
        "lightgray": (211, 211, 211),
        "lightgrey": (211, 211, 211),
        "darkgray": (169, 169, 169),
        "darkgrey": (169, 169, 169),
        "darkblue": (0, 0, 139),
        "navy": (0, 0, 128),
        "darkred": (139, 0, 0),
        "maroon": (128, 0, 0),
        "darkgreen": (0, 100, 0),
        "darkcyan": (0, 139, 139),
        "teal": (0, 128, 128),
        "darkmagenta": (139, 0, 139),
        "purple": (128, 0, 128),
        "violet": (238, 130, 238),
        "darkyellow": (128, 128, 0),
        "olive": (128, 128, 0),
        "orange": (255, 165, 0),
        "brown": (165, 42, 42),
        "gold": (255, 215, 0)
    ]
}

/// Parses `tag-defs` + `fmt-defs` from each `<file><header>` once and maps inline tag ids
/// (`<g id>`, `<bx id>`) to a `TextFormat`. Strictly read-only: never touches the DOM.
///
/// Sources, lowest → highest precedence:
/// 1. the tag-def's `bpt` (or `bx`/`ph`) `name` attribute, e.g. `name="b"` / `name="i"`
/// 2. the escaped original tag text inside `bpt`, e.g. `<cf bold=True italic=True>`, `<sup>`,
///    `<span style="font-weight:bold">`
/// 3. every `<fmt id="N"/>` child of the tag-def, resolved through `<fmt-def id="N"><value key=…>`
public struct FormattingResolver: Sendable {

    /// One dictionary per `<file>` (document order); tag ids are only unique within a file.
    public private(set) var fileFormats: [[String: TextFormat]]

    public static let empty = FormattingResolver(fileFormats: [])

    public init(fileFormats: [[String: TextFormat]]) {
        self.fileFormats = fileFormats
    }

    public init(document: XMLDocument) {
        if let root = document.rootElement() {
            self.init(root: root)
        } else {
            self.init(fileFormats: [])
        }
    }

    public init(root: XMLElement) {
        let files = (root.children ?? [])
            .compactMap { $0 as? XMLElement }
            .filter { xmlLocalName($0) == "file" }
        let scopes = files.isEmpty ? [root] : files
        self.fileFormats = scopes.map { FormattingResolver.parse(scope: $0) }
    }

    public var isEmpty: Bool { fileFormats.allSatisfy { $0.isEmpty } }

    /// Format for a tag-def id in the given file (0-based, document order).
    public func format(forTagID id: String, fileIndex: Int = 0) -> TextFormat? {
        guard fileIndex >= 0, fileIndex < fileFormats.count else { return nil }
        return fileFormats[fileIndex][id]
    }

    /// Format opened by an inline element in a segment (`g` or `bx`); nil for anything else.
    public func format(for element: XMLElement) -> TextFormat? {
        guard !fileFormats.isEmpty else { return nil }
        let name = xmlLocalName(element)
        guard name == "g" || name == "bx",
              let id = FormattingResolver.attr(element, "id") else { return nil }
        let index = fileFormats.count == 1 ? 0 : FormattingResolver.fileIndex(of: element)
        return format(forTagID: id, fileIndex: index)
    }

    /// Index of the enclosing `<file>` among its siblings (0 when not found).
    static func fileIndex(of element: XMLNode) -> Int {
        var node: XMLNode? = element
        while let current = node {
            if let el = current as? XMLElement, xmlLocalName(el) == "file", let parent = el.parent {
                let files = (parent.children ?? [])
                    .compactMap { $0 as? XMLElement }
                    .filter { xmlLocalName($0) == "file" }
                return files.firstIndex(where: { $0 === el }) ?? 0
            }
            node = current.parent
        }
        return 0
    }

    // MARK: - Parsing

    static func parse(scope: XMLElement) -> [String: TextFormat] {
        // Only look in the header (never the body) so large files stay cheap.
        let headers = (scope.children ?? [])
            .compactMap { $0 as? XMLElement }
            .filter { xmlLocalName($0) == "header" }
        let searchRoots: [XMLElement] = headers.isEmpty ? [scope] : headers

        var fmtDefs: [String: TextFormat] = [:]
        var tags: [XMLElement] = []
        for header in searchRoots {
            for element in elementsBelow(header) {
                switch xmlLocalName(element) {
                case "fmt-def":
                    guard let id = FormattingResolver.attr(element, "id") else { continue }
                    var format = TextFormat()
                    for value in childElements(element, named: "value") {
                        guard let key = FormattingResolver.attr(value, "key") else { continue }
                        let text = value.stringValue ?? ""
                        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                        format.apply(key: key, value: text)
                    }
                    fmtDefs[id] = format
                case "tag":
                    // tag-defs/tag only (not e.g. some unrelated "tag" in file-info).
                    if let parent = element.parent as? XMLElement, xmlLocalName(parent) == "tag-defs" {
                        tags.append(element)
                    }
                default:
                    break
                }
            }
        }

        var result: [String: TextFormat] = [:]
        for tag in tags {
            guard let id = FormattingResolver.attr(tag, "id") else { continue }
            var format = TextFormat()
            let children = (tag.children ?? []).compactMap { $0 as? XMLElement }
            if let opener = children.first(where: { ["bpt", "bx"].contains(xmlLocalName($0)) }) {
                if let name = FormattingResolver.attr(opener, "name") {
                    format = format.applying(OriginalTagParser.format(tagName: name, attributes: []))
                }
                if let original = opener.stringValue, !original.isEmpty {
                    format = format.applying(OriginalTagParser.format(fromOriginalTag: original))
                }
            }
            for fmt in children where xmlLocalName(fmt) == "fmt" {
                if let ref = FormattingResolver.attr(fmt, "id"), let def = fmtDefs[ref] {
                    format = format.applying(def)
                }
            }
            if !format.isEmpty {
                result[id] = format
            }
        }
        return result
    }

    /// Attribute lookup that also matches by local name. (swift-corelibs FoundationXML's
    /// `attribute(forName:)` misses attributes on namespaced elements; macOS is unaffected.)
    static func attr(_ element: XMLElement, _ name: String) -> String? {
        if let value = element.attribute(forName: name)?.stringValue {
            return value
        }
        for node in element.attributes ?? [] where (node.localName ?? node.name) == name {
            return node.stringValue
        }
        return nil
    }

    static func childElements(_ element: XMLElement, named name: String) -> [XMLElement] {
        (element.children ?? [])
            .compactMap { $0 as? XMLElement }
            .filter { xmlLocalName($0) == name }
    }
}

/// Best-effort reader for the escaped native tag text Trados stores in `bpt`,
/// e.g. `<cf bold=True size=10>`, `<b>`, `<span style="font-style:italic">`.
public enum OriginalTagParser {

    public static func format(fromOriginalTag raw: String) -> TextFormat {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("<"), !text.hasPrefix("</") else { return TextFormat() }
        text.removeFirst()
        if text.hasSuffix("/>") {
            text.removeLast(2)
        } else if text.hasSuffix(">") {
            text.removeLast()
        }
        let nameEnd = text.firstIndex(where: { $0.isWhitespace }) ?? text.endIndex
        let name = String(text[..<nameEnd])
        let attributes = parseAttributes(String(text[nameEnd...]))
        return format(tagName: name, attributes: attributes)
    }

    public static func format(tagName rawName: String, attributes: [(String, String)]) -> TextFormat {
        let name = (rawName.split(separator: ":").last.map(String.init) ?? rawName).lowercased()
        var format = TextFormat()
        switch name {
        case "b", "strong", "bold": format.bold = true
        case "i", "em", "italic", "cite", "dfn": format.italic = true
        case "u", "ins", "underline": format.underline = true
        case "s", "strike", "del": format.strikethrough = true
        case "sup", "superscript": format.position = .superscript
        case "sub", "subscript": format.position = .subscript
        default: break
        }
        for (key, value) in attributes {
            if key.lowercased() == "style" {
                for declaration in value.split(separator: ";") {
                    let pair = declaration.split(separator: ":", maxSplits: 1).map {
                        $0.trimmingCharacters(in: .whitespaces)
                    }
                    guard pair.count == 2 else { continue }
                    applyCSS(property: pair[0].lowercased(), value: pair[1], to: &format)
                }
            } else {
                format.apply(key: key, value: value)
            }
        }
        return format
    }

    static func applyCSS(property: String, value: String, to format: inout TextFormat) {
        let lower = value.lowercased()
        switch property {
        case "text-decoration", "text-decoration-line":
            if lower.contains("underline") { format.underline = true }
            if lower.contains("line-through") { format.strikethrough = true }
            if lower == "none" { format.underline = false; format.strikethrough = false }
        case "vertical-align":
            format.position = FormatValueParser.position(lower) ?? format.position
        case "background-color", "background":
            if let c = FormatValueParser.color(value) { format.backgroundColor = c }
        default:
            format.apply(key: property, value: value)
        }
    }

    /// Parses `key=value`, `key="value"`, `key='value'` and bare `key` attributes.
    static func parseAttributes(_ text: String) -> [(String, String)] {
        var result: [(String, String)] = []
        let chars = Array(text)
        var i = 0
        func skipSpaces() { while i < chars.count, chars[i].isWhitespace { i += 1 } }
        while i < chars.count {
            skipSpaces()
            guard i < chars.count else { break }
            var key = ""
            while i < chars.count, !chars[i].isWhitespace, chars[i] != "=" {
                key.append(chars[i]); i += 1
            }
            skipSpaces()
            var value = ""
            if i < chars.count, chars[i] == "=" {
                i += 1
                skipSpaces()
                if i < chars.count, chars[i] == "\"" || chars[i] == "'" {
                    let quote = chars[i]; i += 1
                    while i < chars.count, chars[i] != quote { value.append(chars[i]); i += 1 }
                    i += 1
                } else {
                    while i < chars.count, !chars[i].isWhitespace { value.append(chars[i]); i += 1 }
                }
            }
            if !key.isEmpty { result.append((key, value)) }
        }
        return result
    }
}
