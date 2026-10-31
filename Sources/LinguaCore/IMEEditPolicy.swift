import Foundation

/// Pure rules for where IME / typing may replace text in the segment editor.
public enum IMEEditPolicy {
    /// When starting a new composition (no marked range yet), always insert at the
    /// caret with length 0 — never delete existing characters such as trailing `]`.
    public static func replacementRange(
        requested: NSRange,
        caret: NSRange,
        marked: NSRange?,
        composing: Bool
    ) -> NSRange {
        if composing, let marked, marked.location != NSNotFound {
            return marked
        }
        // New composition or plain insert: length-0 at caret.
        _ = requested
        return NSRange(location: caret.location, length: 0)
    }

    /// After an opening row click that created the editor, the caret must be at end
    /// — not at the click point (often index of `]` in `[Redacted]`).
    public static func openingCaretLocation(textLength: Int) -> Int {
        max(0, textLength)
    }
}
