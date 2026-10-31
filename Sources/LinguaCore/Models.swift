import Foundation

/// Stable identity for a bilingual segment: trans-unit id + segment mid.
/// History restore rematches by this key so UUIDs are not regenerated.
public struct SegmentKey: Hashable, Codable, CustomStringConvertible {
    public let unitId: String
    public let mid: String

    public init(unitId: String, mid: String) {
        self.unitId = unitId
        self.mid = mid
    }

    public var description: String { "\(unitId)#\(mid)" }
}

/// UI / session status for a segment (maps to sdl:seg conf when present).
public enum SegmentStatus: String, Codable, CaseIterable {
    case original = "原文件"
    case draft = "草稿"
    case confirmed = "已确认"
    case untranslated = "未翻译"

    public var sdlConf: String? {
        switch self {
        case .confirmed: return "Translated"
        case .draft: return "Draft"
        case .original, .untranslated: return nil
        }
    }
}

/// Lightweight view model for one bilingual segment row.
public struct SegmentRow: Identifiable, Equatable {
    public var id: SegmentKey
    public var source: String
    public var target: String
    public var status: SegmentStatus
    public var isLocked: Bool
    public var isUntranslatable: Bool
    public var hasPendingRevisions: Bool

    public init(
        id: SegmentKey,
        source: String,
        target: String,
        status: SegmentStatus = .original,
        isLocked: Bool = false,
        isUntranslatable: Bool = false,
        hasPendingRevisions: Bool = false
    ) {
        self.id = id
        self.source = source
        self.target = target
        self.status = status
        self.isLocked = isLocked
        self.isUntranslatable = isUntranslatable
        self.hasPendingRevisions = hasPendingRevisions
    }

    public var isEditable: Bool {
        !isLocked && !isUntranslatable
    }
}
