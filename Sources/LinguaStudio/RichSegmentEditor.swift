import SwiftUI
import AppKit
#if canImport(LinguaCore)
import LinguaCore
#endif

extension NSAttributedString.Key {
    static let linguaToken = NSAttributedString.Key("LinguaProtectedToken")
    static let linguaRevision = NSAttributedString.Key("LinguaExistingRevision")
}

/// Build an attributed string with tag tokens as protected attachments (or zero-width placeholders).
/// Formatting (bold/italic/…) from `formats` is display-only: it never changes the
/// tokens or the internal draft string, so saving writes exactly what it did before.
func richDraft(
    _ plan: TagPlan,
    _ draft: String,
    showTags: Bool,
    tagStyle: TagDisplayStyle = .full,
    tracking: Bool = false,
    showInvisibles: Bool = false,
    formats: FormattingResolver = .empty
) throws -> NSAttributedString {
    let parts = try plan.split(draft)
    let result = NSMutableAttributedString()
    var stack: [XMLElement] = []
    // Same-segment <bx>…<ex> formatting spans (keyed by rid ?? id).
    var spans: [(key: String, format: TextFormat)] = []
    let font = SegmentTypography.nsFont

    for i in parts.indices {
        let kind = stack
            .compactMap { $0.attribute(forName: "mtype")?.stringValue }
            .last(where: { $0.hasPrefix("x-sdl-") })

        var attrs: [NSAttributedString.Key: Any] = SegmentTypography.baseAppKitAttributes

        // Display formatting: outer → inner <g> formats, then open <bx> spans.
        if !formats.isEmpty {
            let layered = stack.compactMap { formats.format(for: $0) } + spans.map { $0.format }
            let effective = TextFormat.combined(layered)
            if !effective.isEmpty {
                attrs.merge(
                    appKitAttributes(for: effective, text: parts[i]),
                    uniquingKeysWith: { _, new in new }
                )
            }
        }

        // Existing revision styling stays on top of formatting.
        if let kind = kind {
            attrs[.linguaRevision] = true
            if kind == "x-sdl-deleted" {
                attrs[.foregroundColor] = NSColor.systemRed
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attrs[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.12)
            } else {
                // Bright green + wash so tracked CJK stays obvious on the blue selection row.
                attrs[.foregroundColor] = NSColor.systemGreen
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attrs[.backgroundColor] = NSColor.systemGreen.withAlphaComponent(0.18)
            }
        }

        // Keep real spaces/tabs in storage so AppKit word-wraps at boundaries.
        // `InvisibleLayoutManager` draws ·/⇥/⍽ when showInvisibles is on.
        let visible = parts[i]
        let run = NSMutableAttributedString(string: visible, attributes: attrs)

        if tracking && kind == nil && parts[i] != plan.gaps[i] {
            // Diff on raw gaps (storage no longer substitutes ·).
            let oldChars = Array(plan.gaps[i])
            let newChars = Array(visible)
            var prefix = 0
            while prefix < min(oldChars.count, newChars.count),
                  oldChars[prefix] == newChars[prefix] {
                prefix += 1
            }
            var suffix = 0
            while suffix < min(oldChars.count - prefix, newChars.count - prefix),
                  oldChars[oldChars.count - 1 - suffix] == newChars[newChars.count - 1 - suffix] {
                suffix += 1
            }
            let start = String(newChars.prefix(prefix)).utf16.count
            let length = String(newChars[prefix..<(newChars.count - suffix)]).utf16.count
            if length > 0 {
                run.addAttributes(
                    [
                        .foregroundColor: NSColor.systemGreen,
                        .underlineStyle: NSUnderlineStyle.single.rawValue
                    ],
                    range: NSRange(location: start, length: length)
                )
            }
        }

        result.append(run)
        guard i < plan.actions.count else { continue }

        var element: XMLElement?
        var closing = false
        switch plan.actions[i] {
        case .open(let e):
            element = e
            stack.append(e)
        case .close:
            element = stack.popLast()
            closing = true
        case .empty(let n):
            element = n as? XMLElement
            if let e = element {
                let local = xmlLocalName(e)
                let key = e.attribute(forName: "rid")?.stringValue
                    ?? e.attribute(forName: "id")?.stringValue ?? ""
                if local == "bx", let f = formats.format(for: e) {
                    spans.append((key, f))
                } else if local == "ex", let idx = spans.lastIndex(where: { $0.key == key }) {
                    spans.remove(at: idx)
                }
            }
        }

        let name = element.map { xmlLocalName($0) } ?? ""
        let isRevision = element?.attribute(forName: "mtype")?.stringValue?.hasPrefix("x-sdl-") == true

        if showTags && !isRevision && name != "mrk" {
            let id = element?.attribute(forName: "id")?.stringValue ?? name
            let label = closing
                ? tagStyle.closeLabel(id: id, name: name)
                : tagStyle.openLabel(id: id, name: name)
            let textSize = (label as NSString).size(withAttributes: [.font: font])
            let image = NSImage(
                size: NSSize(width: ceil(textSize.width) + 6, height: 17),
                flipped: false
            ) { rect in
                NSColor.systemBlue.withAlphaComponent(0.12).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
                (label as NSString).draw(
                    at: NSPoint(x: 3, y: 1),
                    withAttributes: [.font: font, .foregroundColor: NSColor.systemBlue]
                )
                return true
            }
            let attachment = NSTextAttachment()
            attachment.image = image
            let attributed = NSMutableAttributedString(attachment: attachment)
            attributed.addAttribute(
                .linguaToken,
                value: plan.tokens[i],
                range: NSRange(location: 0, length: attributed.length)
            )
            result.append(attributed)
        } else {
            // Hair space (U+200A) at 1pt keeps a real glyph advance so adjacent CJK /
            // punctuation is never collapsed by NSLayoutManager (ZWSP+0.1pt could).
            result.append(
                NSAttributedString(
                    string: "\u{200A}",
                    attributes: [
                        .linguaToken: plan.tokens[i],
                        .font: NSFont.systemFont(ofSize: 1),
                        .foregroundColor: NSColor.clear,
                        .kern: -0.5
                    ]
                )
            )
        }
    }

    return result
}

/// Render `draft`, falling back to plain text (tokens kept verbatim, so nothing is lost
/// and flush round-trips the exact draft) if the tag plan cannot split it.
func renderDraft(
    _ plan: TagPlan,
    _ draft: String,
    showTags: Bool,
    tagStyle: TagDisplayStyle = .full,
    tracking: Bool,
    showInvisibles: Bool = false,
    formats: FormattingResolver
) -> (NSAttributedString, Error?) {
    do {
        return (
            try richDraft(
                plan, draft, showTags: showTags, tagStyle: tagStyle, tracking: tracking,
                showInvisibles: showInvisibles, formats: formats
            ),
            nil
        )
    } catch {
        let plain = NSAttributedString(
            string: draft,
            attributes: SegmentTypography.baseAppKitAttributes
        )
        return (plain, error)
    }
}

/// Reconstruct the internal draft string (plain text + opaque tokens) from attributed content.
func internalDraft(_ attributed: NSAttributedString) -> String {
    var result = ""
    attributed.enumerateAttribute(
        .linguaToken,
        in: NSRange(location: 0, length: attributed.length)
    ) { value, range, _ in
        if let token = value as? String {
            result += token
        } else {
            let chunk = (attributed.string as NSString).substring(with: range)
            // Display may show ·/⇥ for invisibles; store always wants real whitespace.
            result += denonprinting(chunk)
        }
    }
    return result
}


/// Map an attributed-string UTF-16 selection onto the internal draft UTF-16 range
/// (attachments / hair-space tokens expand to full `⟦…⟧` tokens; · invisibles → spaces).
func draftUTF16Range(
    forAttributedSelection selection: NSRange,
    in attributed: NSAttributedString
) -> NSRange? {
    guard selection.location != NSNotFound, selection.length > 0 else { return nil }
    let full = NSRange(location: 0, length: attributed.length)
    guard NSIntersectionRange(selection, full).length == selection.length else { return nil }

    // Per-UTF16-index map. Previous bug assigned every glyph in a text run to the
    // run's start → selecting "17MAR2026" wrapped the whole "Angers, 17MAR2026".
    var attrToDraft: [Int] = Array(repeating: 0, count: attributed.length + 1)
    var draftUTF16 = 0
    var index = 0
    let ns = attributed.string as NSString
    while index < attributed.length {
        var effective = NSRange()
        let attrs = attributed.attributes(at: index, effectiveRange: &effective)
        let runEnd = NSMaxRange(effective)
        if let token = attrs[.linguaToken] as? String {
            // Attachment / hair-space: one or more attributed units → whole token in draft.
            for i in index..<runEnd {
                attrToDraft[i] = draftUTF16
            }
            draftUTF16 += (token as NSString).length
            index = runEnd
        } else {
            // Plain text (and · invisibles): map each attributed UTF-16 unit forward.
            while index < runEnd {
                attrToDraft[index] = draftUTF16
                let unit = ns.substring(with: NSRange(location: index, length: 1))
                let raw = denonprinting(unit)
                draftUTF16 += max(1, (raw as NSString).length)
                index += 1
            }
        }
    }
    attrToDraft[attributed.length] = draftUTF16
    let start = attrToDraft[selection.location]
    let end = attrToDraft[NSMaxRange(selection)]
    guard end > start else { return nil }
    return NSRange(location: start, length: end - start)
}


/// Caret (length-0) → draft UTF-16 index.
func draftUTF16Index(
    forAttributedLocation location: Int,
    in attributed: NSAttributedString
) -> Int {
    let loc = max(0, min(location, attributed.length))
    if attributed.length == 0 { return 0 }
    if let ranged = draftUTF16Range(
        forAttributedSelection: NSRange(location: min(loc, max(0, attributed.length - 1)), length: 1),
        in: attributed
    ) {
        // If caret was at end, map to end of draft.
        if loc >= attributed.length {
            return NSMaxRange(ranged)
        }
        return ranged.location
    }
    // Empty or failed: walk like draftUTF16Range
    var draftUTF16 = 0
    var index = 0
    let ns = attributed.string as NSString
    while index < attributed.length {
        if index >= loc { return draftUTF16 }
        var effective = NSRange()
        let attrs = attributed.attributes(at: index, effectiveRange: &effective)
        let runEnd = NSMaxRange(effective)
        if let token = attrs[.linguaToken] as? String {
            if loc < runEnd { return draftUTF16 }
            draftUTF16 += (token as NSString).length
            index = runEnd
        } else {
            while index < runEnd {
                if index >= loc { return draftUTF16 }
                let unit = ns.substring(with: NSRange(location: index, length: 1))
                draftUTF16 += max(1, (denonprinting(unit) as NSString).length)
                index += 1
            }
        }
    }
    return draftUTF16
}

/// Map a draft UTF-16 selection onto the attributed-string UTF-16 range
/// (⟦tokens⟧ collapse to attachments / hair-spaces; spaces may become ·).
func attributedUTF16Range(
    forDraftSelection draftSelection: NSRange,
    in attributed: NSAttributedString
) -> NSRange? {
    guard draftSelection.location != NSNotFound, draftSelection.length >= 0 else { return nil }
    let draftStart = draftSelection.location
    let draftEnd = NSMaxRange(draftSelection)

    var attrToDraft: [Int] = Array(repeating: 0, count: attributed.length + 1)
    var draftUTF16 = 0
    var index = 0
    let ns = attributed.string as NSString
    while index < attributed.length {
        var effective = NSRange()
        let attrs = attributed.attributes(at: index, effectiveRange: &effective)
        let runEnd = NSMaxRange(effective)
        if let token = attrs[.linguaToken] as? String {
            for i in index..<runEnd {
                attrToDraft[i] = draftUTF16
            }
            draftUTF16 += (token as NSString).length
            index = runEnd
        } else {
            while index < runEnd {
                attrToDraft[index] = draftUTF16
                let unit = ns.substring(with: NSRange(location: index, length: 1))
                let raw = denonprinting(unit)
                draftUTF16 += max(1, (raw as NSString).length)
                index += 1
            }
        }
    }
    attrToDraft[attributed.length] = draftUTF16

    var attrStart: Int?
    var attrEnd: Int?
    for a in 0...attributed.length {
        let d = attrToDraft[a]
        if attrStart == nil, d >= draftStart { attrStart = a }
        if d >= draftEnd {
            attrEnd = a
            break
        }
    }
    guard let start = attrStart else { return nil }
    let end = attrEnd ?? attributed.length
    let length = max(0, end - start)
    guard start <= attributed.length else { return nil }
    return NSRange(location: start, length: min(length, attributed.length - start))
}


/// AppKit attributes for a resolved SDL format (display-only).
/// Bold/italic/underline stay at `SegmentTypography.pointSize`. Superscript /
/// subscript use ~0.75 of that size plus baseline offset (Word/Trados-like).
func appKitAttributes(for format: TextFormat, text: String = "") -> [NSAttributedString.Key: Any] {
    var attrs: [NSAttributedString.Key: Any] = [:]
    let base = SegmentTypography.pointSize
    let size = (format.isSuperscript || format.isSubscript) ? base * 0.75 : base
    var font: NSFont
    if let name = format.fontName, let named = NSFont(name: name, size: size) {
        font = named
    } else if abs(size - base) < 0.01 {
        font = SegmentTypography.nsFont
    } else {
        font = NSFont(descriptor: SegmentTypography.nsFont.fontDescriptor, size: size)
            ?? NSFont.systemFont(ofSize: size)
    }
    var traits: NSFontDescriptor.SymbolicTraits = []
    if format.isBold { traits.insert(.bold) }
    if format.isItalic { traits.insert(.italic) }
    if !traits.isEmpty {
        let descriptor = font.fontDescriptor.withSymbolicTraits(
            font.fontDescriptor.symbolicTraits.union(traits)
        )
        font = NSFont(descriptor: descriptor, size: size) ?? font
    }
    attrs[.font] = font
    // CJK fonts have no italic face; slant those runs so 斜体 is still visible.
    if format.isItalic, text.unicodeScalars.contains(where: { isCJKScalar($0) }) {
        attrs[.obliqueness] = 0.2
    }
    if format.isSuperscript {
        attrs[.baselineOffset] = base * 0.35
    } else if format.isSubscript {
        attrs[.baselineOffset] = -base * 0.2
    }
    if format.isUnderline {
        attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
    }
    if format.isStrikethrough {
        attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
    }
    if let c = displayableTextColor(format.textColor) {
        attrs[.foregroundColor] = NSColor(
            srgbRed: CGFloat(c.red), green: CGFloat(c.green), blue: CGFloat(c.blue), alpha: CGFloat(c.alpha)
        )
    }
    if let c = format.backgroundColor {
        attrs[.backgroundColor] = NSColor(
            srgbRed: CGFloat(c.red), green: CGFloat(c.green), blue: CGFloat(c.blue),
            alpha: CGFloat(c.alpha) * 0.45
        )
    }
    return attrs
}

private func isCJKScalar(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFF00...0xFFEF:
        return true
    default:
        return false
    }
}

/// Display keys copied from the neighbouring character into typingAttributes.
private let inheritableTypingKeys: [NSAttributedString.Key] = [
    .font, .foregroundColor, .backgroundColor, .underlineStyle,
    .strikethroughStyle, .baselineOffset, .obliqueness
]

/// Typing attributes. When `view` is given, inherit display formatting from the character
/// before (or after) the caret so typing inside a bold run looks bold immediately.
/// Never copies `.linguaToken` / `.linguaRevision` / attachments, so typed text stays plain gap text.
func typingStyle(
    _ tracking: Bool,
    inheritingFrom view: NSTextView? = nil,
    sticky: TextFormat = .plain
) -> [NSAttributedString.Key: Any] {
    var attrs: [NSAttributedString.Key: Any] = SegmentTypography.baseAppKitAttributes
    if let view, let storage = view.textStorage, storage.length > 0 {
        let location = view.selectedRange().location
        for index in [location - 1, location] where index >= 0 && index < storage.length {
            let neighbour = storage.attributes(at: index, effectiveRange: nil)
            if neighbour[.linguaToken] != nil || neighbour[.attachment] != nil {
                continue
            }
            for key in inheritableTypingKeys {
                if let value = neighbour[key] { attrs[key] = value }
            }
            break
        }
    }
    if !sticky.isEmpty {
        attrs.merge(appKitAttributes(for: sticky), uniquingKeysWith: { _, new in new })
    }
    if tracking {
        attrs[.foregroundColor] = NSColor.systemGreen
        attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
    }
    return attrs
}

/// Layout manager for the shared segment editor.
/// Storage keeps real spaces so AppKit wraps on word boundaries; when
/// `showInvisibles` is on we paint ·/⇥/⍽ on top of those glyphs (Trados-style).
/// Hyphenation is always off — soft breaks were splitting "meniscal" → "meni"/"scal".
final class InvisibleLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    var showInvisibles = false

    override init() {
        super.init()
        usesDefaultHyphenation = false
        delegate = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard showInvisibles, let storage = textStorage else { return }
        let ns = storage.string as NSString
        let body = SegmentTypography.nsFont
        // Quiet, small marks centered in the space advance — full-size · at the
        // glyph origin sat against the previous letter and looked crowded.
        let markColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.75)
        let symbolFont = NSFont.systemFont(ofSize: max(8, body.pointSize * 0.55))
        let symbolAttrs: [NSAttributedString.Key: Any] = [
            .font: symbolFont,
            .foregroundColor: markColor
        ]
        var glyphIndex = glyphsToShow.location
        let glyphEnd = NSMaxRange(glyphsToShow)
        while glyphIndex < glyphEnd {
            let charIndex = characterIndexForGlyph(at: glyphIndex)
            if charIndex >= ns.length { break }
            let ch = ns.character(at: charIndex)
            let frag = lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: nil,
                withoutAdditionalLayout: true
            )
            let loc = location(forGlyphAt: glyphIndex)
            // Advance of this glyph (= space width when ch is whitespace).
            let advance: CGFloat = {
                if glyphIndex + 1 < numberOfGlyphs {
                    let next = location(forGlyphAt: glyphIndex + 1)
                    // Same line fragment → horizontal delta is the advance.
                    if abs(next.y - loc.y) < 0.5 { return max(1, next.x - loc.x) }
                }
                // Fallback: fraction of body size (typical space ≈ 0.25em).
                return max(1, body.pointSize * 0.28)
            }()
            let baseX = origin.x + frag.origin.x + loc.x
            let baselineY = origin.y + frag.origin.y + loc.y

            switch ch {
            case 0x0020, 0x00A0:
                // Dot centered in the full space advance, on the x-height midline.
                let diameter = max(1.6, body.pointSize * 0.14)
                let midX = baseX + advance * 0.5
                let midY = baselineY - body.xHeight * 0.5
                let rect = NSRect(
                    x: midX - diameter * 0.5,
                    y: midY - diameter * 0.5,
                    width: diameter,
                    height: diameter
                )
                markColor.setFill()
                NSBezierPath(ovalIn: rect).fill()
            case 0x0009:
                let glyphSize = ("⇥" as NSString).size(withAttributes: symbolAttrs)
                let point = NSPoint(
                    x: baseX + max(0, (advance - glyphSize.width) * 0.5),
                    y: baselineY - symbolFont.ascender
                )
                ("⇥" as NSString).draw(at: point, withAttributes: symbolAttrs)
            default:
                break
            }
            glyphIndex += 1
        }
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldBreakLineByHyphenatingBeforeCharacterAt charIndex: Int
    ) -> Bool {
        false
    }
}

final class SegmentTextView: NSTextView {
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?
    var onLock: (() -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onFormat: ((InlineFormatKind) -> Void)?
    var onAcceptRevision: (() -> Void)?
    var onRejectRevision: (() -> Void)?
    /// When set, next typed characters pick up this style (B/I/U with no selection).
    var stickyFormat: TextFormat = .plain
    /// Index from mouseDown; on mouseUp with no drag, select that single word.
    private var pendingWordClickIndex: Int?
    /// Pushed when resigning first responder so Store.draft receives IME-committed
    /// text *before* AppKit tears down marked ranges or SwiftUI swaps the row.
    var onFlushSnapshot: ((String) -> Void)?
    /// Segment this view is editing; Store.flushEditing only reads a matching editor.
    var segmentKey: SegmentKey?
    /// Mirrors Store.tracking — revision spans are editable only when true.
    var trackingEnabled = false
    /// When true, the next mouseDown only focuses and puts the caret at the end —
    /// it must not place the caret where the user clicked (often just before `]` of
    /// `[Redacted]`). That opening click is the same gesture that opened the editor.
    var ignoreNextMouseCaret = false

    /// Session history (Store) owns undo — never the text view's NSUndoManager.
    override var undoManager: UndoManager? { nil }

    /// Commit any in-progress IME (Chinese etc.) marked range into the text storage,
    /// then return the internal draft string. Safe to call from Store.flushEditing
    /// *before* clearing editingID / resigning first responder.
    func committedInternalDraft() -> String {
        if hasMarkedText() {
            // unmarkText() keeps the composed characters and clears the marked range.
            unmarkText()
        }
        return internalDraft(attributedString())
    }

    /// Clicking another row resigns this view *before* SwiftUI's onTapGesture runs
    /// `Store.choose` → `flushEditing`. Commit IME and push the snapshot first so
    /// Chinese / brackets are not discarded with the marked range.
    @discardableResult
    override func resignFirstResponder() -> Bool {
        let snapshot = committedInternalDraft()
        onFlushSnapshot?(snapshot)
        return super.resignFirstResponder()
    }

    /// True when `range` touches protected content:
    /// - tag tokens always locked
    /// - revision runs locked when Track Changes is OFF (editable when ON)
    func rangeTouchesProtectedContent(_ range: NSRange) -> Bool {
        guard let storage = textStorage, range.location != NSNotFound else { return false }
        let length = storage.length
        guard length > 0 else { return false }
        let start = max(0, min(range.location, length))
        let end = max(start, min(NSMaxRange(range), length))
        let probe = NSRange(location: start, length: max(0, end - start))
        let lockRevisions = !trackingEnabled

        func isProtected(_ attrs: [NSAttributedString.Key: Any]) -> Bool {
            if attrs[.linguaToken] != nil { return true }
            if lockRevisions, attrs[.linguaRevision] != nil { return true }
            return false
        }

        if probe.length == 0 {
            for index in [start - 1, start] where index >= 0 && index < length {
                let attrs = storage.attributes(at: index, effectiveRange: nil)
                guard isProtected(attrs) else { continue }
                if index == start - 1 {
                    // Caret at end of a protected run is OK (append after it).
                    continue
                }
                var effective = NSRange()
                if attrs[.linguaToken] != nil {
                    _ = storage.attribute(.linguaToken, at: index, effectiveRange: &effective)
                } else {
                    _ = storage.attribute(.linguaRevision, at: index, effectiveRange: &effective)
                }
                // Tokens / locked revisions: block caret anywhere inside the run,
                // including at the first character (location == effective.location).
                if start >= effective.location && start < NSMaxRange(effective) {
                    return true
                }
            }
            return false
        }
        var blocked = false
        storage.enumerateAttributes(in: probe) { attrs, _, stop in
            if isProtected(attrs) {
                blocked = true
                stop.pointee = true
            }
        }
        return blocked
    }

    /// Resolve IME / insert replacement range.
    /// - Starting a new composition (`!hasMarkedText`): always length-0 at the caret
    ///   so setMarkedText cannot delete existing characters (e.g. the trailing `]`).
    /// - Continuing composition: replace only the marked range.
    /// - Never overwrite protected tag tokens.
    private func safeReplacementRange(_ replacementRange: NSRange, forIME: Bool) -> NSRange {
        let caret = selectedRange()
        if forIME {
            let marked = hasMarkedText() ? markedRange() : nil
            return IMEEditPolicy.replacementRange(
                requested: replacementRange,
                caret: caret,
                marked: marked,
                composing: hasMarkedText()
            )
        }
        var range = replacementRange
        if range.location == NSNotFound {
            range = caret
        }
        if rangeTouchesProtectedContent(range) {
            return NSRange(location: caret.location, length: 0)
        }
        return range
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        // Always insert-only / marked-range-only — never let IME eat `]` or other text.
        let safe = safeReplacementRange(replacementRange, forIME: true)
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: safe)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let safe = safeReplacementRange(replacementRange, forIME: hasMarkedText())
        super.insertText(string, replacementRange: safe)
    }

    override func mouseDown(with event: NSEvent) {
        if ignoreNextMouseCaret {
            ignoreNextMouseCaret = false
            pendingWordClickIndex = nil
            window?.makeFirstResponder(self)
            let end = NSRange(location: IMEEditPolicy.openingCaretLocation(textLength: (string as NSString).length), length: 0)
            setSelectedRange(end)
            scrollRangeToVisible(end)
            // Do not call super — that would place the caret at the click point
            // (often just before `]`), which then lets IME delete the bracket.
            return
        }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.clickCount == 1, mods.isEmpty, event.type == .leftMouseDown {
            let point = convert(event.locationInWindow, from: nil)
            pendingWordClickIndex = characterIndexForInsertion(at: point)
        } else {
            pendingWordClickIndex = nil
        }
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        let pending = pendingWordClickIndex
        pendingWordClickIndex = nil
        super.mouseUp(with: event)
        // Single click without a drag → select exactly one word (· counts as space).
        guard event.clickCount == 1,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
              let idx = pending,
              selectedRange().length == 0 else { return }
        let word = Self.singleWordRange(in: string as NSString, at: idx)
        guard word.length > 0 else { return }
        // Do not select protected tag tokens as a "word".
        if rangeTouchesProtectedContent(word),
           textStorage?.attribute(.linguaToken, at: word.location, effectiveRange: nil) != nil {
            setSelectedRange(NSRange(location: word.location, length: 0))
            return
        }
        setSelectedRange(word)
    }

    /// Double-click / select-by-word must also treat invisible · as a boundary.
    override func selectionRange(
        forProposedRange proposedCharRange: NSRange,
        granularity: NSSelectionGranularity
    ) -> NSRange {
        guard granularity == .selectByWord else {
            return super.selectionRange(forProposedRange: proposedCharRange, granularity: granularity)
        }
        let len = (string as NSString).length
        guard len > 0 else { return proposedCharRange }
        let idx = min(max(proposedCharRange.location, 0), len - 1)
        return Self.singleWordRange(in: string as NSString, at: idx)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let idx = characterIndexForInsertion(at: point)
        let len = (string as NSString).length
        if len > 0, idx >= 0, idx < len,
           textStorage?.attribute(.linguaRevision, at: idx, effectiveRange: nil) != nil {
            let menu = NSMenu(title: "")
            let accept = menu.addItem(
                withTitle: L10n.t("ctx.acceptRevision"),
                action: #selector(acceptRevisionClicked(_:)),
                keyEquivalent: ""
            )
            accept.target = self
            let reject = menu.addItem(
                withTitle: L10n.t("ctx.rejectRevision"),
                action: #selector(rejectRevisionClicked(_:)),
                keyEquivalent: ""
            )
            reject.target = self
            // Select the revision run under the cursor for clarity.
            var effective = NSRange()
            _ = textStorage?.attribute(.linguaRevision, at: idx, effectiveRange: &effective)
            if effective.length > 0 {
                setSelectedRange(effective)
            }
            return menu
        }
        return super.menu(for: event)
    }

    @objc private func acceptRevisionClicked(_ sender: Any?) {
        onAcceptRevision?()
    }

    @objc private func rejectRevisionClicked(_ sender: Any?) {
        onRejectRevision?()
    }

    /// Word range at `index`, treating nonprinting glyphs (· ⇥ ⍽) as separators
    /// so "TRIATHLON·PROSTHESIS" is two words, not one.
    static func singleWordRange(in ns: NSString, at index: Int) -> NSRange {
        let len = ns.length
        guard len > 0 else { return NSRange(location: 0, length: 0) }
        let i = max(0, min(index, len - 1))
        if isWordSeparator(ns.character(at: i)) {
            return NSRange(location: i, length: 0)
        }
        var start = i
        while start > 0, !isWordSeparator(ns.character(at: start - 1)) {
            start -= 1
        }
        var end = i + 1
        while end < len, !isWordSeparator(ns.character(at: end)) {
            end += 1
        }
        return NSRange(location: start, length: end - start)
    }

    private static func isWordSeparator(_ ch: unichar) -> Bool {
        // Invisible-space stand-ins from `nonprinting`.
        if ch == 0x00B7 || ch == 0x21E5 || ch == 0x237D { return true } // · ⇥ ⍽
        guard let scalar = UnicodeScalar(ch) else { return true }
        if CharacterSet.whitespacesAndNewlines.contains(scalar) { return true }
        if CharacterSet.punctuationCharacters.contains(scalar) { return true }
        return false
    }

    // MARK: - Case cycle (Word-like Shift+F3)

    enum TextCaseStyle {
        case upper, lower, capitalized
    }

    /// UPPER → lower → Capitalize → UPPER …
    func cycleCaseSelection() {
        applyCase(nextCaseStyle(for: caseTransformTarget().text))
    }

    func applyCase(_ style: TextCaseStyle) {
        let target = caseTransformTarget()
        guard target.range.length > 0 else { return }
        if rangeTouchesProtectedContent(target.range),
           textStorage?.attribute(.linguaToken, at: target.range.location, effectiveRange: nil) != nil {
            return
        }
        let transformed = Self.transformCase(target.text, style: style)
        guard transformed != target.text else { return }
        guard shouldChangeText(in: target.range, replacementString: transformed) else { return }
        textStorage?.replaceCharacters(in: target.range, with: transformed)
        didChangeText()
        let newLen = (transformed as NSString).length
        setSelectedRange(NSRange(location: target.range.location, length: newLen))
    }

    private func caseTransformTarget() -> (range: NSRange, text: String) {
        var range = selectedRange()
        let ns = string as NSString
        if range.length == 0, ns.length > 0 {
            let idx = min(range.location, max(0, ns.length - 1))
            range = Self.singleWordRange(in: ns, at: idx)
        }
        guard range.location != NSNotFound,
              NSMaxRange(range) <= ns.length,
              range.length > 0 else {
            return (NSRange(location: 0, length: 0), "")
        }
        return (range, ns.substring(with: range))
    }

    private func nextCaseStyle(for text: String) -> TextCaseStyle {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return .upper }
        let allUpper = letters.allSatisfy { CharacterSet.uppercaseLetters.contains($0) }
        let allLower = letters.allSatisfy { CharacterSet.lowercaseLetters.contains($0) }
        if allUpper { return .lower }
        if allLower { return .capitalized }
        // Title case or mixed → UPPER (Word: Capitalize → UPPER)
        return .upper
    }

    static func transformCase(_ text: String, style: TextCaseStyle) -> String {
        switch style {
        case .upper: return text.uppercased()
        case .lower: return text.lowercased()
        case .capitalized: return capitalizeWords(text)
        }
    }

    /// Capitalize first letter of each word; · / whitespace / punctuation are boundaries.
    static func capitalizeWords(_ text: String) -> String {
        var out = ""
        var newWord = true
        for ch in text {
            let scalars = String(ch).unicodeScalars
            let isSep = scalars.allSatisfy { scalar in
                if scalar.value == 0x00B7 || scalar.value == 0x21E5 || scalar.value == 0x237D { return true }
                return CharacterSet.whitespacesAndNewlines.contains(scalar)
                    || CharacterSet.punctuationCharacters.contains(scalar)
            }
            if isSep {
                out.append(ch)
                newWord = true
            } else if newWord {
                out.append(contentsOf: String(ch).uppercased())
                newWord = false
            } else {
                out.append(contentsOf: String(ch).lowercased())
            }
        }
        return out
    }

    override func keyDown(with event: NSEvent) {

        let chords = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .option, .control, .shift])
        if chords == .command, event.keyCode == 36 {
            onConfirm?()
            return
        }
        if chords == .command,
           event.charactersIgnoringModifiers?.lowercased() == "l" {
            onLock?()
            return
        }
        // ⌘Z / ⌘⇧Z → Store session history (not NSTextView undo).
        if event.charactersIgnoringModifiers?.lowercased() == "z" {
            if chords == [.command, .shift] {
                onRedo?()
                return
            }
            if chords == .command {
                onUndo?()
                return
            }
        }
        // ⌘B / ⌘I / ⌘U → bold / italic / underline
        if chords == .command,
           let ch = event.charactersIgnoringModifiers?.lowercased() {
            let kind: InlineFormatKind?
            switch ch {
            case "b": kind = .bold
            case "i": kind = .italic
            case "u": kind = .underline
            default: kind = nil
            }
            if let kind {
                onFormat?(kind)
                return
            }
        }
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        // Shift+F3 — Word-like case cycle (UPPER → lower → Capitalize).
        // F3 keyCode = 99 on Apple keyboards.
        if event.keyCode == 99,
           chords == .shift || chords == [.shift] {
            cycleCaseSelection()
            return
        }
        super.keyDown(with: event)
    }
}

/// Owns the ONE AppKit editor used by the whole segment grid (Trados-style).
/// Never create per-row NSTextViews inside LazyVStack — mount this shared view
/// into the selected target cell only; all other cells are read-only SwiftUI Text.
@MainActor
final class SharedSegmentEditor {
    static let shared = SharedSegmentEditor()

    let textView: SegmentTextView
    let scrollView: NSScrollView
    /// Host currently embedding `scrollView`, if any.
    private weak var hostView: NSView?

    private init() {
        let view = SegmentTextView(frame: .zero)
        view.isRichText = true
        view.importsGraphics = false
        view.drawsBackground = false
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.autoresizingMask = [.width]
        // Match inactive SwiftUI Text: no leading gutter (was 6+4 and looked indented).
        view.textContainerInset = NSSize(width: 0, height: 2)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.smartInsertDeleteEnabled = false
        view.enabledTextCheckingTypes = 0
        // "Add period with double-space" (not always exposed as a Swift property).
        let periodSel = NSSelectorFromString("setAutomaticPeriodSubstitutionEnabled:")
        if view.responds(to: periodSel) {
            view.perform(periodSel, with: NSNumber(value: false))
        }
        view.allowsUndo = false

        if let storage = view.textStorage, let container = view.textContainer,
           let old = view.layoutManager {
            storage.removeLayoutManager(old)
            let layout = InvisibleLayoutManager()
            storage.addLayoutManager(layout)
            layout.addTextContainer(container)
        }

        let scroll = NSScrollView(frame: .zero)
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        // Do not reserve leading space for the scroller / safe-area insets.
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets()
        scroll.scrollerInsets = NSEdgeInsets()
        if let clip = scroll.contentView as NSClipView? {
            clip.contentInsets = NSEdgeInsets()
            clip.automaticallyAdjustsContentInsets = false
        }
        scroll.documentView = view

        self.textView = view
        self.scrollView = scroll
    }

    /// Embed the shared scroll+text view into `host`. Moves it if it was elsewhere.
    func mount(into host: NSView) {
        if scrollView.superview !== host {
            scrollView.removeFromSuperview()
            host.addSubview(scrollView)
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                scrollView.topAnchor.constraint(equalTo: host.topAnchor),
                scrollView.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                scrollView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: host.trailingAnchor)
            ])
        }
        hostView = host
        // Match text view width to the clip view so wrapping works inside fixed row height.
        if let clip = scrollView.contentView as NSClipView? {
            let width = max(clip.bounds.width, host.bounds.width, 40)
            textView.frame = NSRect(
                x: 0, y: 0,
                width: width,
                height: max(textView.frame.height, clip.bounds.height)
            )
            textView.textContainer?.containerSize = NSSize(
                width: max(0, width - textView.textContainerInset.width * 2),
                height: CGFloat.greatestFiniteMagnitude
            )
        }
    }

    /// Detach only if still embedded in this host (other hosts may have taken it).
    func unmount(from host: NSView) {
        guard scrollView.superview === host else { return }
        scrollView.removeFromSuperview()
        if hostView === host { hostView = nil }
    }
}

/// Segment-row height for the Trados-like grid (source + target share it).
enum SegmentGridMetrics {
    /// From AppSettings: fixed value or derived from font size.
    static var rowHeight: CGFloat { AppSettings.shared.resolvedRowHeight }
}

/// AppKit-backed editor host: mounts the shared SegmentTextView into this cell only.
/// Tag tokens stay protected via attributed attachments. Never allocates a new text view.
struct RichSegmentEditor: NSViewRepresentable {
    let segmentID: SegmentKey
    /// Store.editSession at open time; a change forces a full rebuild from `draft`.
    let session: Int
    let plan: TagPlan
    let draft: String
    let showTags: Bool
    var tagStyle: TagDisplayStyle = .full
    var tracking: Bool = false
    var showInvisibles: Bool = false
    var formats: FormattingResolver = .empty
    let onChange: (String) -> Void
    let onConfirm: () -> Void
    let onCancel: () -> Void
    let onLock: () -> Void
    var onUndo: () -> Void = {}
    var onRedo: () -> Void = {}
    var onFormat: (InlineFormatKind) -> Void = { _ in }
    var onAcceptRevision: () -> Void = {}
    var onRejectRevision: () -> Void = {}
    var onAttach: (SegmentTextView) -> Void = { _ in }
    var onRenderError: (String) -> Void = { _ in }
    /// After Replace: select this draft UTF-16 range instead of jumping/scrolling to top.
    var pendingDraftSelection: NSRange? = nil
    var onConsumePendingDraftSelection: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSView {
        let host = NSView(frame: .zero)
        host.wantsLayer = true
        return host
    }

    func updateNSView(_ host: NSView, context: Context) {
        context.coordinator.parent = self
        let pool = SharedSegmentEditor.shared
        let view = pool.textView

        pool.mount(into: host)

        view.onConfirm = onConfirm
        view.onCancel = onCancel
        view.onLock = onLock
        view.onUndo = onUndo
        view.onRedo = onRedo
        view.onFormat = onFormat
        view.onAcceptRevision = onAcceptRevision
        view.onRejectRevision = onRejectRevision
        view.delegate = context.coordinator

        if let layout = view.layoutManager as? InvisibleLayoutManager {
            if layout.showInvisibles != showInvisibles {
                layout.showInvisibles = showInvisibles
                view.needsDisplay = true
            }
        }

        view.segmentKey = segmentID
        view.trackingEnabled = tracking
        onAttach(view)

        let coord = context.coordinator
        let planSig = plan.tokens.joined(separator: "\u{1e}")
        let state = EditorSync.State(
            viewDraft: internalDraft(view.attributedString()),
            storeDraft: draft,
            lastPushedDraft: coord.lastPushedDraft,
            renderedSegment: coord.renderedSegment,
            renderedSession: coord.renderedSession,
            segment: segmentID,
            session: session,
            tagsChanged: coord.tagsShown != showTags || coord.tagStyleShown != tagStyle || coord.invisiblesShown != showInvisibles
                || coord.typographyToken != AppSettings.shared.typographyToken,
            planChanged: coord.planSignature != planSig,
            composing: view.hasMarkedText()
        )

        if EditorSync.needsReset(state) {
            let (attributed, error) = renderDraft(
                plan, draft, showTags: showTags, tagStyle: tagStyle, tracking: tracking,
                showInvisibles: showInvisibles, formats: formats
            )
            let sameSession = coord.renderedSegment == segmentID && coord.renderedSession == session
            let oldSelection = view.selectedRange()
            view.textStorage?.setAttributedString(attributed)
            // Prefer Replace's pending draft selection; stash attr range so focus-open
            // does not jump the caret to end afterwards.
            if let pending = pendingDraftSelection {
                onConsumePendingDraftSelection()
                let attrSel = attributedUTF16Range(forDraftSelection: pending, in: attributed)
                    ?? NSRange(location: min(pending.location, attributed.length), length: 0)
                coord.pendingAttrSelection = attrSel
                view.setSelectedRange(attrSel)
                view.scrollRangeToVisible(attrSel)
            } else if sameSession {
                coord.pendingAttrSelection = nil
                let loc = min(oldSelection.location, attributed.length)
                let sel = NSRange(location: loc, length: 0)
                view.setSelectedRange(sel)
                view.scrollRangeToVisible(sel)
            } else {
                coord.pendingAttrSelection = nil
                view.ignoreNextMouseCaret = true
                let end = NSRange(location: attributed.length, length: 0)
                view.setSelectedRange(end)
                view.scrollRangeToVisible(end)
            }
            coord.lastPushedDraft = draft
            coord.tagsShown = showTags
            coord.tagStyleShown = tagStyle
            coord.invisiblesShown = showInvisibles
            coord.typographyToken = AppSettings.shared.typographyToken
            coord.planSignature = planSig
            coord.renderedSegment = segmentID
            coord.renderedSession = session
            if let error {
                let message = L10n.tf("msg.tagParse", segmentID.mid, error.localizedDescription)
                DispatchQueue.main.async { onRenderError(message) }
            }
        } else if let pending = pendingDraftSelection {
            // Draft already matches view but Replace still wants a selection (rare).
            onConsumePendingDraftSelection()
            let attributed = view.attributedString()
            let attrSel = attributedUTF16Range(forDraftSelection: pending, in: attributed)
                ?? NSRange(location: min(pending.location, attributed.length), length: 0)
            coord.pendingAttrSelection = attrSel
            view.setSelectedRange(attrSel)
            view.scrollRangeToVisible(attrSel)
        }

        if !view.hasMarkedText() {
            view.typingAttributes = typingStyle(tracking, inheritingFrom: view, sticky: view.stickyFormat)
        }

        // Keep Store.draft in sync when AppKit resigns us before choose()/flushEditing.
        view.onFlushSnapshot = { [weak coord, weak view] snapshot in
            guard let coord, let view else { return }
            guard coord.parent.segmentID == view.segmentKey else { return }
            // Resign during LazyVStack remount can see an empty storage for one beat;
            // never push that empty snapshot over a known good draft.
            if snapshot.isEmpty {
                let prior = coord.lastPushedDraft ?? coord.parent.draft
                if !prior.isEmpty { return }
            }
            coord.lastPushedDraft = snapshot
            coord.parent.onChange(snapshot)
        }

        if coord.focusedSession != session {
            coord.focusedSession = session
            let keep = coord.pendingAttrSelection
            coord.pendingAttrSelection = nil
            view.ignoreNextMouseCaret = true
            if let keep {
                view.setSelectedRange(keep)
                view.scrollRangeToVisible(keep)
            } else {
                let endNow = NSRange(location: (view.string as NSString).length, length: 0)
                view.setSelectedRange(endNow)
                view.scrollRangeToVisible(endNow)
            }
            DispatchQueue.main.async {
                guard view.window != nil else { return }
                view.ignoreNextMouseCaret = true
                view.window?.makeFirstResponder(view)
                if let keep {
                    view.setSelectedRange(keep)
                    view.scrollRangeToVisible(keep)
                } else {
                    let end = NSRange(location: view.string.utf16.count, length: 0)
                    view.setSelectedRange(end)
                    view.scrollRangeToVisible(end)
                }
                DispatchQueue.main.async {
                    view.ignoreNextMouseCaret = false
                }
            }
        } else {
            coord.pendingAttrSelection = nil
        }
    }

    static func dismantleNSView(_ host: NSView, coordinator: Coordinator) {
        SharedSegmentEditor.shared.unmount(from: host)
        // Do not destroy the shared text view — only detach from this host.
        _ = coordinator
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichSegmentEditor
        var tagsShown: Bool?
        var tagStyleShown: TagDisplayStyle?
        var invisiblesShown: Bool?
        var typographyToken: Int?
        var focusedSession: Int?
        /// Attr selection to keep across focus-open after Replace.
        var pendingAttrSelection: NSRange?
        /// Last draft we pushed to the text view or reported via onChange.
        var lastPushedDraft: String?
        var planSignature: String?
        var renderedSegment: SegmentKey?
        var renderedSession: Int?

        init(_ parent: RichSegmentEditor) {
            self.parent = parent
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            if let view = notification.object as? SegmentTextView, !view.hasMarkedText() {
                view.typingAttributes = typingStyle(parent.tracking, inheritingFrom: view, sticky: view.stickyFormat)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? SegmentTextView else { return }
            // Reject updates that do not belong to the segment this host was opened for.
            if let key = view.segmentKey, key != parent.segmentID {
                return
            }
            // While IME composition is active, do not push partial pinyin into Store.draft.
            if view.hasMarkedText() {
                return
            }
            let draft = internalDraft(view.attributedString())
            let selection = view.selectedRange()
            let (attributed, _) = renderDraft(
                parent.plan,
                draft,
                showTags: parent.showTags,
                tagStyle: parent.tagStyle,
                tracking: parent.tracking,
                showInvisibles: parent.showInvisibles,
                formats: parent.formats
            )
            // Always re-apply typing attrs; invisibles are drawn by the layout manager
            // so the string may change even though the internal draft did not.
            view.textStorage?.setAttributedString(attributed)
            view.setSelectedRange(
                NSRange(location: min(selection.location, attributed.length), length: 0)
            )
            view.typingAttributes = typingStyle(parent.tracking, inheritingFrom: view, sticky: view.stickyFormat)
            lastPushedDraft = draft
            parent.onChange(draft)
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let storage = textView.textStorage else { return false }
            var allowed = true
            let lockRevisions = !parent.tracking
            storage.enumerateAttributes(
                in: NSRange(location: 0, length: storage.length)
            ) { attrs, range, stop in
                let isToken = attrs[.linguaToken] != nil
                let isRevision = attrs[.linguaRevision] != nil
                guard isToken || (lockRevisions && isRevision) else { return }

                let intersects = NSIntersectionRange(range, affectedCharRange).length > 0
                // Include caret at the start of a locked run (previously slipped through).
                let caretInOrAtStart =
                    affectedCharRange.length == 0
                    && affectedCharRange.location >= range.location
                    && affectedCharRange.location < NSMaxRange(range)
                if intersects || caretInOrAtStart {
                    allowed = false
                    stop.pointee = true
                }
            }
            if !allowed {
                NSSound.beep()
            }
            return allowed
        }
    }
}
