import Foundation

/// Options for find / replace in segment text.
public struct SearchOptions: Equatable {
    public var caseSensitive: Bool
    public var wholeWord: Bool
    public var useRegex: Bool

    public init(caseSensitive: Bool = false, wholeWord: Bool = false, useRegex: Bool = false) {
        self.caseSensitive = caseSensitive
        self.wholeWord = wholeWord
        self.useRegex = useRegex
    }
}

/// Result of a tag-safe gap replace on one segment target.
public enum GapReplaceResult: Equatable {
    case applied(newDraft: String, count: Int, replacedDraftUTF16: NSRange?)
    /// Visible text has a match that spans a protected tag — skip the segment.
    case skippedUnsafe
    /// Only matches sit inside locked track-change gaps (记录修订 OFF).
    case skippedLocked
    case noMatch
    case invalidPattern
}

/// Find / replace helpers that never mutate TagPlan tokens.
public enum SearchReplace {

    /// Ranges of all matches of `pattern` inside `text`.
    public static func matchRanges(
        in text: String,
        pattern: String,
        options: SearchOptions
    ) -> [Range<String.Index>]? {
        guard !pattern.isEmpty else { return [] }

        if options.useRegex || options.wholeWord {
            guard let regex = makeRegex(pattern: pattern, options: options) else {
                return nil
            }
            let nsRange = NSRange(text.startIndex..., in: text)
            return regex.matches(in: text, range: nsRange).compactMap { match in
                Range(match.range, in: text)
            }
        }

        var ranges: [Range<String.Index>] = []
        var searchFrom = text.startIndex
        let compare: String.CompareOptions = options.caseSensitive ? [] : [.caseInsensitive]
        while searchFrom < text.endIndex,
              let found = text.range(of: pattern, options: compare, range: searchFrom..<text.endIndex) {
            ranges.append(found)
            searchFrom = found.upperBound
        }
        return ranges
    }

    public static func matchCount(
        in text: String,
        pattern: String,
        options: SearchOptions
    ) -> Int? {
        matchRanges(in: text, pattern: pattern, options: options)?.count
    }

    public static func textMatches(
        _ text: String,
        query: String,
        options: SearchOptions
    ) -> Bool {
        if query.isEmpty { return true }
        guard let ranges = matchRanges(in: text, pattern: query, options: options) else {
            return false
        }
        return !ranges.isEmpty
    }

    /// First match as a draft UTF-16 `NSRange`, optionally starting at/after `startFromUTF16`.
    /// Matches that end at or before `startFromUTF16` are skipped (same rule as firstOnly replace).
    public static func firstMatchDraftUTF16(
        in text: String,
        pattern: String,
        options: SearchOptions,
        startFromUTF16: Int = 0
    ) -> NSRange? {
        guard let ranges = matchRanges(in: text, pattern: pattern, options: options) else {
            return nil
        }
        for range in ranges {
            let loc = (text[..<range.lowerBound] as NSString).length
            let len = (String(text[range]) as NSString).length
            if loc + len <= startFromUTF16 { continue }
            return NSRange(location: loc, length: len)
        }
        return nil
    }

    /// Convert a Swift string range to draft UTF-16 NSRange.
    public static func utf16Range(of range: Range<String.Index>, in text: String) -> NSRange {
        let loc = (text[..<range.lowerBound] as NSString).length
        let len = (String(text[range]) as NSString).length
        return NSRange(location: loc, length: len)
    }

    /// Replace within each TagPlan gap independently. Tokens are never touched.
    /// If the joined plain text has more matches than the sum of per-gap matches,
    /// at least one hit crosses a tag → `.skippedUnsafe`.
    ///
    /// - Parameters:
    ///   - firstOnly: replace only the first eligible match (at/after `startFromDraftUTF16`).
    ///   - startFromDraftUTF16: draft UTF-16 index; matches that end at or before this are skipped
    ///     when `firstOnly` (so Replace after a prior hit advances past the selection).
    ///   - allowRevisionEdits: when false, matches inside `plan.revisionGaps` are locked.
    public static func replaceInGaps(
        plan: TagPlan,
        find: String,
        replacement: String,
        options: SearchOptions,
        firstOnly: Bool = false,
        startFromDraftUTF16: Int = 0,
        allowRevisionEdits: Bool = true
    ) -> GapReplaceResult {
        replaceInGapList(
            gaps: plan.gaps,
            tokens: plan.tokens,
            revisionGaps: plan.revisionGaps,
            find: find,
            replacement: replacement,
            options: options,
            firstOnly: firstOnly,
            startFromDraftUTF16: startFromDraftUTF16,
            allowRevisionEdits: allowRevisionEdits
        )
    }

    /// Replace only inside the currently editable draft string (must already be a valid TagPlan draft).
    public static func replaceInDraft(
        plan: TagPlan,
        draft: String,
        find: String,
        replacement: String,
        options: SearchOptions,
        firstOnly: Bool = false,
        startFromDraftUTF16: Int = 0,
        allowRevisionEdits: Bool = true
    ) -> GapReplaceResult {
        guard let parts = try? plan.split(draft) else {
            return .skippedUnsafe
        }
        return replaceInGapList(
            gaps: parts,
            tokens: plan.tokens,
            revisionGaps: plan.revisionGaps,
            find: find,
            replacement: replacement,
            options: options,
            firstOnly: firstOnly,
            startFromDraftUTF16: startFromDraftUTF16,
            allowRevisionEdits: allowRevisionEdits
        )
    }

    // MARK: - Private

    private static func replaceInGapList(
        gaps: [String],
        tokens: [String],
        revisionGaps: [Bool],
        find: String,
        replacement: String,
        options: SearchOptions,
        firstOnly: Bool,
        startFromDraftUTF16: Int,
        allowRevisionEdits: Bool
    ) -> GapReplaceResult {
        guard !find.isEmpty else { return .noMatch }
        guard gaps.count == tokens.count + 1 else { return .skippedUnsafe }
        let revMask: [Bool] = {
            if revisionGaps.count == gaps.count { return revisionGaps }
            return Array(repeating: false, count: gaps.count)
        }()

        let plain = gaps.joined()
        guard let plainRanges = matchRanges(in: plain, pattern: find, options: options) else {
            return .invalidPattern
        }
        if plainRanges.isEmpty {
            return .noMatch
        }

        // Draft UTF-16 offsets of each gap start (tokens included between gaps).
        var gapDraftStarts: [Int] = []
        var draftCursor = 0
        for i in gaps.indices {
            gapDraftStarts.append(draftCursor)
            draftCursor += (gaps[i] as NSString).length
            if i < tokens.count {
                draftCursor += (tokens[i] as NSString).length
            }
        }

        var gapMatchTotal = 0
        var lockedMatchCount = 0
        var newGaps = gaps
        var applied = 0
        var replacedDraftUTF16: NSRange?

        gapLoop: for i in gaps.indices {
            let gap = gaps[i]
            guard let ranges = matchRanges(in: gap, pattern: find, options: options) else {
                return .invalidPattern
            }
            gapMatchTotal += ranges.count
            let locked = !allowRevisionEdits && revMask[i]

            if ranges.isEmpty { continue }

            if locked {
                lockedMatchCount += ranges.count
                continue
            }

            if firstOnly {
                let gapStart = gapDraftStarts[i]
                for range in ranges {
                    let matchStart = gapStart + utf16Offset(of: range.lowerBound, in: gap)
                    let matchLen = (String(gap[range]) as NSString).length
                    let matchEnd = matchStart + matchLen
                    // Skip matches that end at/before the caret/selection end.
                    if matchEnd <= startFromDraftUTF16 { continue }

                    let (updated, count) = replaceRanges(in: gap, ranges: [range], replacement: replacement)
                    guard count == 1 else { continue }
                    newGaps[i] = updated
                    applied = 1
                    let replLen = (replacement as NSString).length
                    replacedDraftUTF16 = NSRange(location: matchStart, length: replLen)
                    break gapLoop
                }
            } else {
                let (updated, count) = replaceRanges(in: gap, ranges: ranges, replacement: replacement)
                newGaps[i] = updated
                applied += count
                if replacedDraftUTF16 == nil, let first = ranges.first {
                    let matchStart = gapDraftStarts[i] + utf16Offset(of: first.lowerBound, in: gap)
                    replacedDraftUTF16 = NSRange(
                        location: matchStart,
                        length: (replacement as NSString).length
                    )
                }
            }
        }

        if plainRanges.count > gapMatchTotal {
            return .skippedUnsafe
        }
        if applied == 0 {
            if lockedMatchCount > 0 {
                return .skippedLocked
            }
            // firstOnly past the last match, or all matches were before startFrom
            return .noMatch
        }

        var draft = newGaps[0]
        for i in tokens.indices {
            draft += tokens[i] + newGaps[i + 1]
        }
        return .applied(newDraft: draft, count: applied, replacedDraftUTF16: replacedDraftUTF16)
    }

    private static func utf16Offset(of index: String.Index, in text: String) -> Int {
        (text[..<index] as NSString).length
    }

    private static func makeRegex(pattern: String, options: SearchOptions) -> NSRegularExpression? {
        var body = pattern
        if !options.useRegex {
            body = NSRegularExpression.escapedPattern(for: pattern)
        }
        if options.wholeWord {
            body = "\\b(?:\(body))\\b"
        }
        var opts: NSRegularExpression.Options = []
        if !options.caseSensitive {
            opts.insert(.caseInsensitive)
        }
        return try? NSRegularExpression(pattern: body, options: opts)
    }

    /// Replace from the end so earlier indices stay valid.
    private static func replaceRanges(
        in text: String,
        ranges: [Range<String.Index>],
        replacement: String
    ) -> (String, Int) {
        guard !ranges.isEmpty else { return (text, 0) }
        var result = text
        for range in ranges.reversed() {
            result.replaceSubrange(range, with: replacement)
        }
        return (result, ranges.count)
    }
}
