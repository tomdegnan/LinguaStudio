import Foundation

/// Chooses which draft string to commit when leaving a segment.
///
/// Leaving a row can race with IME resign and with a stale/reused NSTextView:
/// the live editor may briefly show stripped text (missing `[]` or CJK) while
/// `storeDraft` still holds the last good onChange value (or vice versa).
/// Prefer the longest TagPlan-valid live candidate (editor / store). Fall back
/// to `plan` only when neither live candidate is usable — never restore `plan`
/// over an intentional user shortening that already landed in `store`.
///
/// Select/filter remount race: both live candidates can briefly be `""` while
/// `plan` still has the real target. Empty is TagPlan-valid for plain segments,
/// so a naive "prefer live" wipe would empty the DOM — refuse that.
public enum FlushPolicy {

    public struct Candidates: Equatable {
        /// Live NSTextView internal draft (after unmarking IME), if any.
        public var editor: String?
        /// Store.draft last pushed via onChange / startEditing.
        public var store: String
        /// Current plan.text (DOM). Floor when live candidates are unusable.
        public var plan: String

        public init(editor: String?, store: String, plan: String) {
            self.editor = editor
            self.store = store
            self.plan = plan
        }
    }

    /// Returns the draft to pass to `applyEdit`.
    public static func draftToCommit(
        _ candidates: Candidates,
        split: (String) throws -> [String]
    ) -> String {
        func usable(_ value: String?) -> String? {
            guard let value, (try? split(value)) != nil else { return nil }
            return value
        }

        // Remount / filter-select race: shared editor + store both empty for a
        // moment while the DOM still has text. Never flush that empty string.
        if !candidates.plan.isEmpty {
            let editorEmpty = candidates.editor == nil || candidates.editor?.isEmpty == true
            if editorEmpty && candidates.store.isEmpty {
                return usable(candidates.plan) ?? candidates.plan
            }
        }

        let live = [usable(candidates.editor), usable(candidates.store)]
            .compactMap { $0 }

        if let best = live.max(by: { $0.count < $1.count }) {
            // Prefer editor when it ties with store (most recent committed IME).
            if let editor = usable(candidates.editor), editor.count == best.count {
                return editor
            }
            return best
        }

        return usable(candidates.plan) ?? candidates.plan
    }

    /// True when committing `proposed` would drop content that `baseline` still has
    /// (e.g. editor lost `[]` or CJK while store/plan still has them).
    public static func wouldLoseContent(proposed: String, baseline: String) -> Bool {
        if proposed == baseline { return false }
        if baseline.isEmpty { return false }
        if proposed.count >= baseline.count { return false }
        return isSubsequence(proposed, of: baseline)
    }

    private static func isSubsequence(_ short: String, of long: String) -> Bool {
        if short.isEmpty { return true }
        var i = short.startIndex
        for ch in long {
            if ch == short[i] {
                i = short.index(after: i)
                if i == short.endIndex { return true }
            }
        }
        return false
    }
}
