import Foundation

/// Foundation's XML parser drops whitespace-only text nodes between tags.
/// We temporarily replace those runs with opaque tokens, parse, then restore.
public enum WhitespacePreservingParser {

    /// Parse UTF-8 XML while keeping significant inter-tag whitespace intact.
    public static func parse(_ data: Data) throws -> XMLDocument {
        guard let original = String(data: data, encoding: .utf8) else {
            throw LinguaError.message(
                "Only UTF-8 encoded SDLXLIFF files are supported. / 暂时仅支持 UTF-8 编码的 SDLXLIFF。"
            )
        }

        let pattern = try NSRegularExpression(pattern: "(?<=>)[ \\t\\r\\n]+(?=<)")
        let nsRange = NSRange(original.startIndex..., in: original)
        // Only tokenize whitespace *inside* the root element. Whitespace in the
        // prolog (e.g. between `<?xml …?>` and `<xliff>`) or after the root end
        // must stay as-is, otherwise the token becomes top-level text and the
        // XML parser rejects the document.
        let ns = original as NSString
        let rootStart = (try NSRegularExpression(pattern: "<[A-Za-z_]"))
            .firstMatch(in: original, range: nsRange)?.range.location ?? 0
        let rootEnd = ns.range(of: ">", options: .backwards).location
        let matches = pattern.matches(in: original, range: nsRange).filter {
            $0.range.location > rootStart
                && (rootEnd == NSNotFound || $0.range.location + $0.range.length <= rootEnd)
        }

        // Unique prefix so tokens cannot collide with document text.
        let tokenPrefix =
            "LINGUA"
            + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            + "SPACE"

        var prepared = original
        var tokens: [(token: String, whitespace: String)] = []

        for (index, match) in matches.enumerated().reversed() {
            guard let range = Range(match.range, in: prepared) else { continue }
            let whitespace = String(prepared[range])
            let token = tokenPrefix + String(index) + "END"
            tokens.append((token, whitespace))
            prepared.replaceSubrange(range, with: token)
        }

        let document = try XMLDocument(xmlString: prepared, options: [.nodePreserveAll])

        for node in try document.nodes(forXPath: "//text()") {
            var value = node.stringValue ?? ""
            guard value.contains(tokenPrefix) else { continue }
            for (token, whitespace) in tokens where value.contains(token) {
                value = value.replacingOccurrences(of: token, with: whitespace)
            }
            node.stringValue = value
        }

        return document
    }
}
