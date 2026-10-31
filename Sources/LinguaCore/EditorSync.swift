import Foundation

/// Decides when the inline editor must rebuild its text storage from the store's draft.
///
/// Rules (when not composing):
/// - Always reset on first paint, segment change, edit-session change, tags/plan change.
/// - Reset when the view is stale: it matches neither `storeDraft` nor `lastPushedDraft`
///   (reused NSView showing old text while the store already has the real draft).
/// - Reset when the store moved externally (undo/reload/segment re-open already covered
///   by session): `storeDraft != lastPushedDraft` and the view is still at `lastPushedDraft`.
/// - Do NOT reset when the view is ahead of the store (`viewDraft == lastPushedDraft` but
///   store still lags). That happens around Chinese IME commit: the text view already has
///   测试 while a queued SwiftUI refresh still carries the previous store draft. Resetting
///   then was wiping the Chinese characters (the "选中就丢字" bug with 记录修订 on).
public enum EditorSync {
    public struct State: Equatable {
        public var viewDraft: String
        public var storeDraft: String
        public var lastPushedDraft: String?
        public var renderedSegment: SegmentKey?
        public var renderedSession: Int?
        public var segment: SegmentKey
        public var session: Int
        public var tagsChanged: Bool
        public var planChanged: Bool
        public var composing: Bool

        public init(
            viewDraft: String, storeDraft: String, lastPushedDraft: String?,
            renderedSegment: SegmentKey?, renderedSession: Int?,
            segment: SegmentKey, session: Int,
            tagsChanged: Bool = false, planChanged: Bool = false, composing: Bool = false
        ) {
            self.viewDraft = viewDraft
            self.storeDraft = storeDraft
            self.lastPushedDraft = lastPushedDraft
            self.renderedSegment = renderedSegment
            self.renderedSession = renderedSession
            self.segment = segment
            self.session = session
            self.tagsChanged = tagsChanged
            self.planChanged = planChanged
            self.composing = composing
        }
    }

    public static func needsReset(_ s: State) -> Bool {
        if s.composing { return false }

        if s.lastPushedDraft == nil
            || s.renderedSegment != s.segment
            || s.renderedSession != s.session
            || s.tagsChanged
            || s.planChanged {
            return true
        }

        if s.viewDraft == s.storeDraft {
            return false
        }

        let last = s.lastPushedDraft
        // View is the authority for in-flight typing / IME commit.
        if s.viewDraft == last {
            return false
        }
        // Store moved externally (undo etc.) while the view still shows the old push.
        if s.storeDraft != last && last != nil {
            return true
        }
        // View matches neither store nor last push → reused/stale cell.
        return true
    }

    /// Previous (buggy) rule: skipped reset when store == lastPushed even if the view was stale.
    public static func legacyNeedsReset(_ s: State) -> Bool {
        let storeMovedAhead = s.storeDraft != s.lastPushedDraft && s.viewDraft != s.storeDraft
        return s.lastPushedDraft == nil || s.tagsChanged || s.planChanged || storeMovedAhead
    }

    /// The over-eager rule from the first fix attempt: reset whenever view != store.
    /// That wiped Chinese right after IME commit when a stale SwiftUI frame still had
    /// the pre-commit store draft.
    public static func eagerNeedsReset(_ s: State) -> Bool {
        if s.composing { return false }
        return s.lastPushedDraft == nil
            || s.renderedSegment != s.segment
            || s.renderedSession != s.session
            || s.tagsChanged
            || s.planChanged
            || s.viewDraft != s.storeDraft
    }
}
