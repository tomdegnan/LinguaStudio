import SwiftUI
import AppKit
#if canImport(LinguaCore)
import LinguaCore
#endif

/// How inline tags are drawn when "显示标签" is on.
enum TagDisplayStyle: String, CaseIterable, Identifiable {
    case full
    case short

    var id: String { rawValue }

    var label: String {
        switch self {
        case .full: return L10n.t("tagStyle.full")
        case .short: return L10n.t("tagStyle.short")
        }
    }

    func openLabel(id: String, name: String = "") -> String {
        switch self {
        case .full:
            let shown = id.isEmpty ? (name.isEmpty ? "?" : name) : id
            return "‹\(shown)›"
        case .short:
            return "→"
        }
    }

    func closeLabel(id: String, name: String = "") -> String {
        switch self {
        case .full:
            let shown = id.isEmpty ? (name.isEmpty ? "?" : name) : id
            return "‹/\(shown)›"
        case .short:
            return "←"
        }
    }
}

/// Render XML segment content for inactive source/target cells.
/// Always keeps real spaces in the string (so wrapping is word-boundary). When
/// `showInvisibles` is on, `SegmentStaticText` paints ·/⇥/⍽ via the same
/// `InvisibleLayoutManager` as the live editor — never substitutes `·` into the text.
func displayXML(
    _ node: XMLNode,
    showTags: Bool,
    tagStyle: TagDisplayStyle = .full,
    showInvisibles: Bool = false,
    formats: FormattingResolver = .empty
) -> SegmentStaticText {
    var builder = SegmentDisplayBuilder(
        showTags: showTags,
        tagStyle: tagStyle,
        formats: formats
    )
    builder.visit(node)
    return SegmentStaticText(attributed: builder.output, showInvisibles: showInvisibles)
}

/// Read-only AppKit text for inactive rows. Real spaces + optional invisible marks.
struct SegmentStaticText: NSViewRepresentable {
    let attributed: NSAttributedString
    let showInvisibles: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> StaticSegmentTextView {
        let view = StaticSegmentTextView(frame: .zero)
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = true
        view.drawsBackground = false
        view.backgroundColor = .clear
        view.textContainerInset = NSSize(width: 0, height: 0)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.autoresizingMask = [.width]
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.font = SegmentTypography.nsFont
        view.textColor = .labelColor
        view.insertionPointColor = .labelColor
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.enabledTextCheckingTypes = 0

        if let storage = view.textStorage, let container = view.textContainer,
           let old = view.layoutManager {
            storage.removeLayoutManager(old)
            let layout = InvisibleLayoutManager()
            storage.addLayoutManager(layout)
            layout.addTextContainer(container)
            context.coordinator.layout = layout
        }
        return view
    }

    func updateNSView(_ view: StaticSegmentTextView, context: Context) {
        let layout = context.coordinator.layout
            ?? (view.layoutManager as? InvisibleLayoutManager)
        if layout?.showInvisibles != showInvisibles {
            layout?.showInvisibles = showInvisibles
            view.needsDisplay = true
        }
        context.coordinator.layout = layout

        let current = view.textStorage?.string ?? ""
        let next = attributed.string
        let attrsChanged = view.textStorage?.isEqual(to: attributed) != true
        if current != next || attrsChanged {
            view.textStorage?.setAttributedString(attributed)
            view.invalidateIntrinsicContentSize()
            view.needsDisplay = true
        }
    }

    final class Coordinator {
        var layout: InvisibleLayoutManager?
    }
}

/// Self-sizing read-only text view: width from parent, height from used text rect.
final class StaticSegmentTextView: NSTextView {
    override var intrinsicContentSize: NSSize {
        guard let layout = layoutManager, let container = textContainer else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 0)
        }
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        let height = ceil(used.height + textContainerInset.height * 2)
        return NSSize(width: NSView.noIntrinsicMetric, height: max(height, ceil(SegmentTypography.pointSize + 4)))
    }

    override func layout() {
        super.layout()
        let width = max(bounds.width, 1)
        if let container = textContainer {
            let target = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            if container.containerSize != target {
                container.containerSize = target
                invalidateIntrinsicContentSize()
            }
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if let container = textContainer {
            container.containerSize = NSSize(
                width: max(newSize.width, 1),
                height: CGFloat.greatestFiniteMagnitude
            )
        }
        invalidateIntrinsicContentSize()
    }
}

/// Walks a segment tree and emits an AppKit `NSAttributedString`.
/// Nested `<g>` formats combine outer → inner (inner explicit values win); `<bx>`…`<ex>`
/// spans inside the same segment are layered on top. Revision styling is applied last.
/// Spaces stay as U+0020 — never replaced with · (wrapping must stay word-boundary).
struct SegmentDisplayBuilder {
    let showTags: Bool
    let tagStyle: TagDisplayStyle
    let formats: FormattingResolver

    private(set) var output = NSMutableAttributedString()
    private var formatStack: [TextFormat] = []
    private var spans: [(key: String, format: TextFormat)] = []
    private var revisionStack: [String] = []

    init(showTags: Bool, tagStyle: TagDisplayStyle, formats: FormattingResolver) {
        self.showTags = showTags
        self.tagStyle = tagStyle
        self.formats = formats
    }

    private var effectiveFormat: TextFormat {
        TextFormat.combined(formatStack + spans.map { $0.format })
    }

    mutating func visit(_ node: XMLNode) {
        if node.kind == .text {
            // Real whitespace only — invisibles are painted by InvisibleLayoutManager.
            appendText(node.stringValue ?? "")
            return
        }

        guard let element = node as? XMLElement else {
            for child in node.children ?? [] { visit(child) }
            return
        }

        let name = xmlLocalName(element)
        let subtype = element.attribute(forName: "mtype")?.stringValue ?? ""

        if name == "mrk" {
            let isRevision = subtype == "x-sdl-deleted" || subtype == "x-sdl-added"
            if isRevision { revisionStack.append(subtype) }
            for child in element.children ?? [] { visit(child) }
            if isRevision { revisionStack.removeLast() }
            return
        }

        let id = element.attribute(forName: "id")?.stringValue ?? ""
        let children = element.children ?? []

        appendChip(tagStyle.openLabel(id: id, name: name))

        switch name {
        case "bx":
            if let format = formats.format(for: element) {
                spans.append((spanKey(element), format))
            }
        case "ex":
            let key = spanKey(element)
            if let index = spans.lastIndex(where: { $0.key == key }) {
                spans.remove(at: index)
            }
        default:
            break
        }

        guard !children.isEmpty else { return }

        let pushed = formats.format(for: element)
        if let pushed { formatStack.append(pushed) }
        for child in children { visit(child) }
        if pushed != nil { formatStack.removeLast() }

        appendChip(tagStyle.closeLabel(id: id, name: name))
    }

    private func spanKey(_ element: XMLElement) -> String {
        element.attribute(forName: "rid")?.stringValue
            ?? element.attribute(forName: "id")?.stringValue
            ?? ""
    }

    private mutating func appendChip(_ label: String) {
        guard showTags else { return }
        var attrs = SegmentTypography.baseAppKitAttributes
        attrs[.foregroundColor] = NSColor.systemBlue
        output.append(NSAttributedString(string: label, attributes: attrs))
    }

    private mutating func appendText(_ text: String) {
        guard !text.isEmpty else { return }
        var attrs = SegmentTypography.baseAppKitAttributes
        let format = effectiveFormat
        if !format.isEmpty {
            attrs.merge(appKitAttributes(for: format, text: text), uniquingKeysWith: { _, new in new })
        }
        if let revision = revisionStack.last {
            if revision == "x-sdl-deleted" {
                attrs[.foregroundColor] = NSColor.systemRed
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attrs[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.12)
            } else {
                attrs[.foregroundColor] = NSColor.systemGreen
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attrs[.backgroundColor] = NSColor.systemGreen.withAlphaComponent(0.18)
            }
        }
        output.append(NSAttributedString(string: text, attributes: attrs))
    }
}

/// Shared typography for inactive SwiftUI cells and the live NSTextView.
/// Keeps font metrics / invisible-space glyph widths identical so selection does not "jump".
/// Reads live values from AppSettings (UserDefaults-backed).
enum SegmentTypography {
    static var pointSize: CGFloat { CGFloat(AppSettings.shared.fontSize) }
    static var nsFont: NSFont {
        let size = pointSize
        if let name = AppSettings.shared.resolvedFontName,
           let font = NSFont(name: name, size: size) {
            return font
        }
        return NSFont.systemFont(ofSize: size)
    }
    static var swiftUIFont: Font {
        let size = pointSize
        if let name = AppSettings.shared.resolvedFontName {
            return Font.custom(name, size: size)
        }
        return Font.system(size: size)
    }
    static var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        // Unicode line breaking so invisible-space stand-ins (·) are BA break
        // opportunities — AppKit's default push-out wrap treats "a·b·c" as one word
        // and then hyphenates mid-token ("meni"/"scal").
        style.lineBreakStrategy = .standard
        style.hyphenationFactor = 0
        style.lineSpacing = 0
        style.paragraphSpacing = 0
        style.alignment = .natural
        style.allowsDefaultTighteningForTruncation = false
        return style
    }
    static var baseAppKitAttributes: [NSAttributedString.Key: Any] {
        [
            .font: nsFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle,
            .kern: 0
        ]
    }
}

/// Base point size used for formatted runs (matches the table's body text on macOS).
var formattedBaseFontSize: CGFloat { SegmentTypography.pointSize }

/// Text colours this close to black/white are ignored so they don't vanish in Dark/Light mode
/// (Trados/Word often write an explicit `TextColor=Black`).
func displayableTextColor(_ colour: RGBAColor?) -> RGBAColor? {
    guard let colour else { return nil }
    let lum = colour.luminance
    return (lum < 0.08 || lum > 0.92) ? nil : colour
}

/// SwiftUI attributes for a resolved SDL format. FontSize is intentionally not applied
/// (keeps the grid readable, like Studio's default editor view); FontName is.
func swiftUIAttributes(for format: TextFormat) -> AttributeContainer {
    var container = AttributeContainer()
    // Bold/italic/underline: full body size. Super/sub: ~0.75 + baseline.
    let base = formattedBaseFontSize
    let size = (format.isSuperscript || format.isSubscript) ? base * 0.75 : base
    let needsFont = format.isBold || format.isItalic || format.fontName != nil
        || format.isSuperscript || format.isSubscript
    if needsFont {
        var font: Font
        if let name = format.fontName {
            font = Font.custom(name, size: size)
        } else if abs(size - base) < 0.01 {
            font = SegmentTypography.swiftUIFont
        } else {
            font = Font.system(size: size)
        }
        if format.isBold { font = font.bold() }
        if format.isItalic { font = font.italic() }
        container.swiftUI.font = font
    }
    if format.isSuperscript {
        container.swiftUI.baselineOffset = formattedBaseFontSize * 0.35
    } else if format.isSubscript {
        container.swiftUI.baselineOffset = -formattedBaseFontSize * 0.2
    }
    if format.isUnderline {
        container.swiftUI.underlineStyle = .single
    }
    if format.isStrikethrough {
        container.swiftUI.strikethroughStyle = .single
    }
    if let colour = displayableTextColor(format.textColor) {
        container.swiftUI.foregroundColor = Color(
            .sRGB, red: colour.red, green: colour.green, blue: colour.blue, opacity: colour.alpha
        )
    }
    if let colour = format.backgroundColor {
        container.swiftUI.backgroundColor = Color(
            .sRGB, red: colour.red, green: colour.green, blue: colour.blue, opacity: colour.alpha * 0.45
        )
    }
    return container
}

/// Legacy string substitution for invisibles. Prefer painting via
/// `InvisibleLayoutManager` — substituting middle-dot removes word boundaries
/// and causes mid-word wraps (LABORA/TORY). Kept for denonprinting / tests only.
func nonprinting(_ text: String, show: Bool) -> String {
    guard show else { return text }
    return text
        .replacingOccurrences(of: " ", with: "·")
        .replacingOccurrences(of: "\t", with: "⇥")
        .replacingOccurrences(of: "\n", with: "↵\n")
        .replacingOccurrences(of: "\u{00a0}", with: "⍽")
}

/// Inverse of `nonprinting` for reconstructing the internal draft from the editor display.
func denonprinting(_ text: String) -> String {
    text
        .replacingOccurrences(of: "·", with: " ")
        .replacingOccurrences(of: "⇥", with: "\t")
        .replacingOccurrences(of: "↵\n", with: "\n")
        .replacingOccurrences(of: "↵", with: "\n")
        .replacingOccurrences(of: "⍽", with: "\u{00a0}")
}

