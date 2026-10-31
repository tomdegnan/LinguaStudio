import Foundation

/// Creates and resolves SDL track-changes markers under `doc-info` / `sdl:rev-defs`.
public enum RevisionFactory {

    private static let sdlDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "MM/dd/yyyy HH:mm:ss"
        return formatter
    }()

    /// Ensure `sdl` namespace is declared on the xliff root.
    public static func ensureSDLNamespace(on document: XMLDocument) {
        guard let root = document.rootElement() else { return }
        if root.resolveNamespace(forName: "sdl:revid") == nil {
            root.addNamespace(
                XMLNode.namespace(withName: "sdl", stringValue: SDLNamespaces.sdl) as! XMLNode
            )
        }
    }

    /// Locate or create `sdl:rev-defs` under `doc-info`.
    public static func revDefs(in document: XMLDocument) throws -> XMLElement {
        guard let info = try document.nodes(forXPath: "//*[local-name()='doc-info']").first as? XMLElement else {
            throw LinguaError.message(
                "File is missing SDL doc-info (required for track changes). / 文件缺少 SDL 修订信息容器。"
            )
        }

        if let existing = try info.nodes(forXPath: "./*[local-name()='rev-defs']").first as? XMLElement {
            return existing
        }

        ensureSDLNamespace(on: document)
        let defs = XMLElement(name: "sdl:rev-defs", uri: SDLNamespaces.sdl)
        info.addChild(defs)
        return defs
    }

    /// Build an `mrk` revision marker and register a matching `sdl:rev-def`.
    public static func makeMarker(
        text: String,
        deleted: Bool,
        document: XMLDocument,
        author: String,
        date: Date = Date()
    ) throws -> XMLElement {
        ensureSDLNamespace(on: document)
        let defs = try revDefs(in: document)
        let revisionId = UUID().uuidString.lowercased()

        let definition = XMLElement(name: "sdl:rev-def", uri: SDLNamespaces.sdl)
        setAttribute(definition, "id", revisionId)
        setAttribute(definition, "author", author)
        setAttribute(definition, "date", sdlDateFormatter.string(from: date))
        if deleted {
            setAttribute(definition, "type", "Delete")
        }
        defs.addChild(definition)

        let marker = XMLElement(name: "mrk", uri: SDLNamespaces.xliff)
        setAttribute(marker, "mtype", deleted ? "x-sdl-deleted" : "x-sdl-added")
        setAttribute(marker, "sdl:revid", revisionId)
        marker.addChild(XMLNode.text(withStringValue: text) as! XMLNode)
        return marker
    }

    /// Accept or reject all pending revision markers under a segment target root.
    /// - accept: keep added text, drop deleted text
    /// - reject: drop added text, restore deleted text
    public static func resolve(_ root: XMLElement, accept: Bool) throws {
        let markers = revisionElements(in: root)
        for marker in markers.reversed() {
            guard let parent = marker.parent as? XMLElement else { continue }
            let deleted = marker.attribute(forName: "mtype")?.stringValue == "x-sdl-deleted"
            let index = marker.index
            let children = (marker.children ?? []).map { $0.copy() as! XMLNode }
            marker.detach()
            // Keep children when: accepting an addition, or rejecting a deletion.
            let keepChildren = deleted != accept
            if keepChildren {
                for (offset, child) in children.enumerated() {
                    parent.insertChild(child, at: index + offset)
                }
            }
        }
    }

    public static func hasPending(in root: XMLNode) -> Bool {
        !revisionElements(in: root).isEmpty
    }
}

// MARK: - Review navigation helpers

extension RevisionFactory {

    /// Keys of rows that currently have pending SDL revision markers.
    public static func pendingKeys(in rows: [SegmentRow]) -> [SegmentKey] {
        rows.filter(\.hasPendingRevisions).map(\.id)
    }

    /// Next pending key after `current` within `orderedKeys` (wraps). Nil if none.
    public static func nextPending(
        after current: SegmentKey?,
        in orderedKeys: [SegmentKey]
    ) -> SegmentKey? {
        guard !orderedKeys.isEmpty else { return nil }
        guard let current,
              let index = orderedKeys.firstIndex(of: current) else {
            return orderedKeys.first
        }
        let next = orderedKeys.index(after: index)
        return next < orderedKeys.endIndex ? orderedKeys[next] : orderedKeys.first
    }

    /// Previous pending key before `current` within `orderedKeys` (wraps). Nil if none.
    public static func previousPending(
        before current: SegmentKey?,
        in orderedKeys: [SegmentKey]
    ) -> SegmentKey? {
        guard !orderedKeys.isEmpty else { return nil }
        guard let current,
              let index = orderedKeys.firstIndex(of: current) else {
            return orderedKeys.last
        }
        if index == orderedKeys.startIndex {
            return orderedKeys.last
        }
        return orderedKeys[orderedKeys.index(before: index)]
    }
}
