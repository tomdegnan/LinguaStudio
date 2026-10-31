import SwiftUI
import AppKit

@main
struct LinguaApp: App {
    @StateObject private var store = Store()
    @ObservedObject private var settings = AppSettings.shared

    init() {
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: "NSAutomaticPeriodSubstitutionEnabled")
        defaults.set(false, forKey: "NSAutomaticQuoteSubstitutionEnabled")
        defaults.set(false, forKey: "NSAutomaticDashSubstitutionEnabled")
        defaults.set(false, forKey: "NSAutomaticTextReplacementEnabled")
        defaults.set(false, forKey: "NSAutomaticSpellingCorrectionEnabled")
    }

    var body: some Scene {
        WindowGroup("Lingua Studio") {
            ContentView()
                .environmentObject(store)
                .environmentObject(settings)
                // Do NOT `.id(localeToken)` here — remounting tears down NSToolbar,
                // drops ControlGroup chrome, and can scramble item order (file vs workflow).
                // L10n reads AppSettings live; EnvironmentObject refresh is enough.
        }
        .windowToolbarStyle(.unified)
        .commands {
            // App observes `settings`; localeToken publish rebuilds commands/titles
            // without remounting ContentView / NSToolbar.
            CommandGroup(replacing: .appSettings) {
                Button(L10n.t("menu.settings")) {
                    store.showSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .undoRedo) {
                Button(L10n.t("menu.undo")) { store.undoLatest() }
                    .keyboardShortcut("z", modifiers: .command)
                Button(L10n.t("menu.redo")) { store.redoLatest() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(after: .textEditing) {
                Button(L10n.t("menu.bold")) { store.applyFormat(.bold) }
                    .keyboardShortcut("b", modifiers: .command)
                Button(L10n.t("menu.italic")) { store.applyFormat(.italic) }
                    .keyboardShortcut("i", modifiers: .command)
                Button(L10n.t("menu.underline")) { store.applyFormat(.underline) }
                    .keyboardShortcut("u", modifiers: .command)
                Button(L10n.t("menu.superscript")) { store.applyFormat(.superscript) }
                Button(L10n.t("menu.subscript")) { store.applyFormat(.subscript) }
                Divider()
                Button(L10n.t("menu.cycleCase")) { store.cycleCase() }
                    .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF3FunctionKey)!)), modifiers: .shift)
                Button(L10n.t("menu.upperCase")) { store.applyCase(.upper) }
                Button(L10n.t("menu.lowerCase")) { store.applyCase(.lower) }
                Button(L10n.t("menu.capitalizedCase")) { store.applyCase(.capitalized) }
                Divider()
                Button(L10n.t("menu.findNext")) { store.findNext() }
                    .keyboardShortcut("g", modifiers: .command)
                Button(L10n.t("menu.findPrev")) { store.findPrevious() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                Divider()
                Button(L10n.t("menu.openReplace")) { store.openReplacePanel() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Button(L10n.t("menu.replace")) { store.replaceCurrent() }
                Button(L10n.t("menu.replaceAll")) { store.replaceAll() }
            }

            CommandMenu(L10n.t("menu.review")) {
                Button(store.reviewMode ? L10n.t("menu.exitReview") : L10n.t("menu.enterReview")) {
                    store.toggleReviewMode()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                Divider()
                Button(L10n.t("menu.nextPending")) { store.goToPending(next: true) }
                    .keyboardShortcut(.downArrow, modifiers: .command)
                Button(L10n.t("menu.prevPending")) { store.goToPending(next: false) }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                Divider()
                Button(L10n.t("menu.acceptSeg")) { store.review(accept: true) }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                Button(L10n.t("menu.rejectSeg")) { store.review(accept: false) }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
                Button(L10n.t("menu.acceptAll")) { store.reviewAll(accept: true) }
                Button(L10n.t("menu.rejectAll")) { store.reviewAll(accept: false) }
            }
        }

        // Floating Find/Replace panel — not a modal sheet (no dimming).
        Window(L10n.t("replace.title"), id: "replace") {
            ReplaceSheetView()
                .environmentObject(store)
                .environmentObject(settings)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 440, height: 280)
    }
}
