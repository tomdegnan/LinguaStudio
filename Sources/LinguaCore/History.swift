import Foundation

/// Serialized document state for session undo/redo.
public struct EditSnapshot: Equatable {
    public var data: Data
    public var selectionKey: SegmentKey?
    public var statuses: [String: String]  // SegmentKey.description -> SegmentStatus.rawValue
    /// Visible target text per segment (for history sidebar before→after previews).
    public var targets: [String: String]

    public init(
        data: Data,
        selectionKey: SegmentKey?,
        statuses: [String: String],
        targets: [String: String] = [:]
    ) {
        self.data = data
        self.selectionKey = selectionKey
        self.statuses = statuses
        self.targets = targets
    }
}

public struct HistoryEntry: Identifiable {
    public let id: UUID
    public let date: Date
    public let title: String
    /// Compact human-readable change, e.g. `"Redacted" → "redacted"` or status-only.
    public let detail: String
    public let before: EditSnapshot
    public let after: EditSnapshot

    public init(title: String, before: EditSnapshot, after: EditSnapshot, detail: String? = nil) {
        self.id = UUID()
        self.date = Date()
        self.title = title
        self.before = before
        self.after = after
        self.detail = detail ?? HistoryDiff.preview(before: before, after: after)
    }
}

/// Builds short before→after strings for the history sidebar.
public enum HistoryDiff {
    public static let defaultMaxSide = 36
    public static let maxLines = 3

    public static func preview(
        before: EditSnapshot,
        after: EditSnapshot,
        maxSide: Int = defaultMaxSide
    ) -> String {
        let keys = Set(before.targets.keys).union(after.targets.keys)
            .union(before.statuses.keys).union(after.statuses.keys)
        var lines: [String] = []
        for key in keys.sorted() {
            let bText = before.targets[key] ?? ""
            let aText = after.targets[key] ?? ""
            if bText != aText {
                lines.append("\(truncate(bText, maxSide)) → \(truncate(aText, maxSide))")
                continue
            }
            let bStatus = before.statuses[key]
            let aStatus = after.statuses[key]
            if bStatus != aStatus {
                lines.append("\(displayStatus(bStatus)) → \(displayStatus(aStatus))")
            }
        }
        if lines.isEmpty { return "" }
        if lines.count <= maxLines {
            return lines.joined(separator: "\n")
        }
        let head = lines.prefix(maxLines).joined(separator: "\n")
        return head + "\n…"
    }

    public static func truncate(_ text: String, _ maxSide: Int) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.isEmpty { return "∅" }
        if collapsed.count <= maxSide { return "“\(collapsed)”" }
        let idx = collapsed.index(collapsed.startIndex, offsetBy: maxSide)
        return "“\(collapsed[..<idx])…”"
    }

    private static func displayStatus(_ raw: String?) -> String {
        switch raw {
        case "draft", "Draft": return "草稿"
        case "confirmed", "Confirmed": return "已确认"
        case "untranslated", "Untranslated": return "未翻译"
        case nil, "": return "—"
        default: return raw ?? "—"
        }
    }
}

/// Session-only undo/redo stack (default depth 100).
public final class HistoryManager {
    public private(set) var entries: [HistoryEntry] = []
    public private(set) var position: Int = 0
    public var maxDepth: Int

    public init(maxDepth: Int = 100) {
        self.maxDepth = maxDepth
    }

    public var canUndo: Bool { position > 0 }
    public var canRedo: Bool { position < entries.count }

    public func clear() {
        entries = []
        position = 0
    }

    /// True when committing `after` should create a history entry.
    public static func shouldRecord(before: EditSnapshot, after: EditSnapshot) -> Bool {
        before.data != after.data || before.statuses != after.statuses
    }

    public func record(before: EditSnapshot, after: EditSnapshot, title: String) {
        guard Self.shouldRecord(before: before, after: after) else { return }
        if position < entries.count {
            entries.removeSubrange(position...)
        }
        entries.append(HistoryEntry(title: title, before: before, after: after))
        if entries.count > maxDepth {
            entries.removeFirst(entries.count - maxDepth)
        }
        position = entries.count
    }

    /// Snapshot to restore when moving to `newPosition` (0 = before first edit).
    public func snapshot(at newPosition: Int) -> EditSnapshot? {
        guard newPosition >= 0, newPosition <= entries.count else { return nil }
        if newPosition == 0 {
            return entries.first?.before
        }
        return entries[newPosition - 1].after
    }

    public func move(to newPosition: Int) -> EditSnapshot? {
        guard let snap = snapshot(at: newPosition) else { return nil }
        position = newPosition
        return snap
    }
}
