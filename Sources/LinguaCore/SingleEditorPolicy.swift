import Foundation

/// Rules for the Trados-like single shared editor: at most one segment hosts
/// the live AppKit editor; switching always flushes the previous segment first.
public enum SingleEditorPolicy {

    /// Result of attempting to move the single editor slot from `current` to `next`.
    public struct Transition: Equatable {
        /// Segment that should own the live editor after the call (nil = none).
        public var active: SegmentKey?
        /// True when the previous editor contents were successfully committed (or there was none).
        public var flushed: Bool

        public init(active: SegmentKey?, flushed: Bool) {
            self.active = active
            self.flushed = flushed
        }
    }

    /// Flush-before-choose. If `flush` returns false, keep `current` active and report failure.
    /// When flush succeeds, `next` becomes the sole active editor segment (may be nil).
    public static func choose(
        current: SegmentKey?,
        next: SegmentKey?,
        flush: () -> Bool
    ) -> Transition {
        guard flush() else {
            return Transition(active: current, flushed: false)
        }
        return Transition(active: next, flushed: true)
    }

    /// Invariant used by tests and UI: only one segment may be conceptually editing.
    public static func isSingleActive(editingID: SegmentKey?, selected: SegmentKey?) -> Bool {
        // Either no editor, or the editor is exactly the selected row.
        guard let editingID else { return true }
        return editingID == selected
    }
}
