import Foundation

/// XLIFF 1.2 and SDL namespace URIs used throughout Trados SDLXLIFF.
public enum SDLNamespaces {
    public static let xliff = "urn:oasis:names:tc:xliff:document:1.2"
    public static let sdl = "http://sdl.com/FileTypes/SdlXliff/1.0"
}

public enum LinguaError: LocalizedError {
    case message(String)

    public var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

public func linguaError(_ message: String) -> NSError {
    NSError(
        domain: "LinguaStudio",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: message]
    )
}

/// Local name of an XML element, ignoring any prefix.
public func xmlLocalName(_ node: XMLNode) -> String {
    if let element = node as? XMLElement {
        return element.localName ?? element.name ?? ""
    }
    return node.localName ?? node.name ?? ""
}

/// Depth-first list of all element descendants.
public func elementsBelow(_ root: XMLNode, includeSelf: Bool = false) -> [XMLElement] {
    var result: [XMLElement] = []
    if includeSelf, let element = root as? XMLElement {
        result.append(element)
    }
    for child in root.children ?? [] {
        if let element = child as? XMLElement {
            result.append(element)
        }
        result.append(contentsOf: elementsBelow(child, includeSelf: false))
    }
    return result
}

/// Set or replace a named attribute on an element.
public func setAttribute(_ element: XMLElement, _ name: String, _ value: String) {
    if let existing = element.attribute(forName: name) {
        existing.stringValue = value
    } else {
        element.addAttribute(XMLNode.attribute(withName: name, stringValue: value) as! XMLNode)
    }
}

/// Collect revision marker elements (`mrk` with x-sdl-added / x-sdl-deleted).
public func revisionElements(in root: XMLNode) -> [XMLElement] {
    elementsBelow(root).filter { element in
        xmlLocalName(element) == "mrk"
            && ["x-sdl-added", "x-sdl-deleted"].contains(
                element.attribute(forName: "mtype")?.stringValue ?? ""
            )
    }
}

/// Visible plain text: skips deleted revision markers.
public func visibleText(_ node: XMLNode) -> String {
    if let element = node as? XMLElement,
       element.attribute(forName: "mtype")?.stringValue == "x-sdl-deleted" {
        return ""
    }
    if node.kind == .text {
        return node.stringValue ?? ""
    }
    return (node.children ?? []).map { visibleText($0) }.joined()
}
