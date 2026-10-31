import SwiftUI
import AppKit

/// Persisted general preferences (UserDefaults). Drive SegmentTypography + grid metrics.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Key {
        static let fontFamily = "lingua.settings.fontFamily"
        static let fontSize = "lingua.settings.fontSize"
        static let rowHeightFollowsFont = "lingua.settings.rowHeightFollowsFont"
        static let fixedRowHeight = "lingua.settings.fixedRowHeight"
        static let showTags = "lingua.settings.showTags"
        static let tagStyle = "lingua.settings.tagStyle"
        static let showInvisibles = "lingua.settings.showInvisibles"
        static let appearance = "lingua.settings.appearance"
        static let confirmAdvancesToNext = "lingua.settings.confirmAdvancesToNext"
        static let maxHistorySteps = "lingua.settings.maxHistorySteps"
        static let trackingDefault = "lingua.settings.trackingDefault"
        static let showHistoryPanel = "lingua.settings.showHistoryPanel"
        static let uiLanguage = "lingua.settings.uiLanguage"
    }

    /// Display name in picker; empty string = system font.
    @Published var fontFamily: String {
        didSet { defaults.set(fontFamily, forKey: Key.fontFamily); bumpTypography() }
    }
    @Published var fontSize: Double {
        didSet {
            defaults.set(fontSize, forKey: Key.fontSize)
            bumpTypography()
        }
    }
    @Published var rowHeightFollowsFont: Bool {
        didSet {
            defaults.set(rowHeightFollowsFont, forKey: Key.rowHeightFollowsFont)
            bumpTypography()
        }
    }
    @Published var fixedRowHeight: Double {
        didSet {
            defaults.set(fixedRowHeight, forKey: Key.fixedRowHeight)
            bumpTypography()
        }
    }
    @Published var showTags: Bool {
        didSet { defaults.set(showTags, forKey: Key.showTags) }
    }
    /// `"full"` or `"short"`.
    @Published var tagStyleRaw: String {
        didSet { defaults.set(tagStyleRaw, forKey: Key.tagStyle) }
    }
    @Published var showInvisibles: Bool {
        didSet { defaults.set(showInvisibles, forKey: Key.showInvisibles) }
    }
    /// `system` | `light` | `dark`
    @Published var appearanceRaw: String {
        didSet {
            defaults.set(appearanceRaw, forKey: Key.appearance)
            applyAppearance()
        }
    }
    @Published var confirmAdvancesToNext: Bool {
        didSet { defaults.set(confirmAdvancesToNext, forKey: Key.confirmAdvancesToNext) }
    }
    @Published var maxHistorySteps: Int {
        didSet {
            let clamped = min(500, max(10, maxHistorySteps))
            if clamped != maxHistorySteps {
                maxHistorySteps = clamped
                return
            }
            defaults.set(maxHistorySteps, forKey: Key.maxHistorySteps)
        }
    }
    @Published var trackingDefault: Bool {
        didSet { defaults.set(trackingDefault, forKey: Key.trackingDefault) }
    }
    @Published var showHistoryPanel: Bool {
        didSet { defaults.set(showHistoryPanel, forKey: Key.showHistoryPanel) }
    }
    /// `zh` | `en` — UI language (default Chinese).
    @Published var uiLanguageRaw: String {
        didSet {
            defaults.set(uiLanguageRaw, forKey: Key.uiLanguage)
            localeToken &+= 1
        }
    }

    /// Bumped whenever font / row metrics change so SwiftUI + NSTextView re-render.
    @Published private(set) var typographyToken: Int = 0
    /// Bumped when UI language changes so menus/views refresh.
    @Published private(set) var localeToken: Int = 0

    private let defaults = UserDefaults.standard

    static let fontChoiceIDs: [String] = [
        "", "SF Mono", "Menlo", "Monaco", "Helvetica Neue", "Arial",
        "PingFang SC", "Songti SC", "Courier New"
    ]

    static func fontLabel(for id: String) -> String {
        switch id {
        case "": return L10n.t("font.system")
        case "PingFang SC": return L10n.t("font.pingfang")
        case "Songti SC": return L10n.t("font.songti")
        default: return id
        }
    }

    private init() {
        let d = UserDefaults.standard
        fontFamily = d.string(forKey: Key.fontFamily) ?? ""
        let size = d.object(forKey: Key.fontSize) as? Double ?? Double(NSFont.systemFontSize)
        fontSize = min(20, max(11, size))
        rowHeightFollowsFont = d.object(forKey: Key.rowHeightFollowsFont) as? Bool ?? true
        fixedRowHeight = d.object(forKey: Key.fixedRowHeight) as? Double ?? 84
        showTags = d.object(forKey: Key.showTags) as? Bool ?? true
        tagStyleRaw = d.string(forKey: Key.tagStyle) ?? "full"
        showInvisibles = d.object(forKey: Key.showInvisibles) as? Bool ?? false
        appearanceRaw = d.string(forKey: Key.appearance) ?? "system"
        confirmAdvancesToNext = d.object(forKey: Key.confirmAdvancesToNext) as? Bool ?? true
        maxHistorySteps = d.object(forKey: Key.maxHistorySteps) as? Int ?? 100
        trackingDefault = d.object(forKey: Key.trackingDefault) as? Bool ?? false
        showHistoryPanel = d.object(forKey: Key.showHistoryPanel) as? Bool ?? true
        uiLanguageRaw = d.string(forKey: Key.uiLanguage) ?? "zh"
        applyAppearance()
    }

    var tagStyle: TagDisplayStyle {
        get { tagStyleRaw == "short" ? .short : .full }
        set { tagStyleRaw = newValue == .short ? "short" : "full" }
    }

    var uiLanguage: AppLanguage {
        get { AppLanguage(rawValue: uiLanguageRaw) ?? .zh }
        set { uiLanguageRaw = newValue.rawValue }
    }

    var appearance: AppAppearance {
        get { AppAppearance(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue }
    }

    /// Resolved PostScript / face name for NSFont; nil = system.
    var resolvedFontName: String? {
        let name = fontFamily.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    var resolvedRowHeight: CGFloat {
        if rowHeightFollowsFont {
            return max(56, CGFloat(fontSize) * 6.5)
        }
        return CGFloat(min(200, max(48, fixedRowHeight)))
    }

    func bumpTypography() {
        typographyToken &+= 1
    }

    func applyAppearance() {
        // NSApp is nil while AppSettings.shared is first touched from Store.init
        // during SwiftUI @StateObject setup — skip until the app object exists.
        guard let app = NSApp else { return }
        switch appearance {
        case .system:
            app.appearance = nil
        case .light:
            app.appearance = NSAppearance(named: .aqua)
        case .dark:
            app.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func resetToDefaults() {
        fontFamily = ""
        fontSize = Double(NSFont.systemFontSize)
        rowHeightFollowsFont = true
        fixedRowHeight = 84
        showTags = true
        tagStyleRaw = "full"
        showInvisibles = false
        appearanceRaw = "system"
        confirmAdvancesToNext = true
        maxHistorySteps = 100
        trackingDefault = false
        showHistoryPanel = true
        uiLanguageRaw = "zh"
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return L10n.t("appearance.system")
        case .light: return L10n.t("appearance.light")
        case .dark: return L10n.t("appearance.dark")
        }
    }
}
