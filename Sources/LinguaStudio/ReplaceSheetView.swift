import SwiftUI
import AppKit

/// Movable floating Find & Replace panel (⌘⇧H). Not a modal sheet — main window stays active.
/// Replace Find is independent of the table filter; Replace scans the document directly.
/// Return/Enter runs Replace once (same as 「替换」). Debounced so onSubmit + default
/// button cannot fire twice in one keypress (that skipped past the result before confirm).
struct ReplaceSheetView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    /// Guards against Enter triggering both TextField.onSubmit and the default button.
    @State private var lastReplaceAt: Date? = nil

    private var canReplace: Bool {
        !store.findText.isEmpty && !store.reviewMode && store.document != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.t("replace.title"))
                    .font(.headline)
                Spacer()
                Button(L10n.t("replace.done")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Form {
                TextField(L10n.t("replace.find"), text: $store.findText)
                    .onSubmit { performReplace() }
                TextField(L10n.t("replace.with"), text: $store.replaceWith)
                    .onSubmit { performReplace() }
                HStack(spacing: 12) {
                    Toggle(L10n.t("search.case"), isOn: $store.caseSensitive)
                        .toggleStyle(.checkbox)
                        .help(L10n.t("search.case.help"))
                    Toggle(L10n.t("search.word"), isOn: $store.wholeWord)
                        .toggleStyle(.checkbox)
                        .help(L10n.t("search.word.help"))
                    Toggle(L10n.t("search.regex"), isOn: $store.useRegex)
                        .toggleStyle(.checkbox)
                        .help(L10n.t("search.regex.help"))
                    Spacer(minLength: 0)
                }
            }
            .formStyle(.grouped)

            if store.replaceRegexInvalid {
                Text(L10n.t("search.regexInvalid"))
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack(spacing: 10) {
                Button(L10n.t("search.prev")) { store.findReplacePrevious() }
                Button(L10n.t("search.next")) { store.findReplaceNext() }
                if store.replaceMatchCount > 0 {
                    Text("\(store.replaceMatchIndex) / \(store.replaceMatchCount)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.t("search.replaceOne")) { performReplace() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canReplace)
                    .help(L10n.t("search.replace.help"))
                Button(L10n.t("search.replaceAll")) { store.replaceAll() }
                    .disabled(!canReplace)
                    .help(L10n.t("search.replaceAll.help"))
            }
        }
        .padding(16)
        .frame(width: 440, height: 280)
        .background(FloatingReplacePanelConfigurer())
    }

    private func performReplace() {
        guard canReplace else { return }
        let now = Date()
        if let last = lastReplaceAt, now.timeIntervalSince(last) < 0.25 {
            return
        }
        lastReplaceAt = now
        store.replaceCurrent()
    }
}

/// Makes the Replace window a floating utility panel: draggable, no dimming, editor usable behind it.
private struct FloatingReplacePanelConfigurer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.configure(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.configure(from: nsView) }
    }

    private static func configure(from view: NSView) {
        guard let window = view.window else { return }
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.hidesOnDeactivate = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        if window.styleMask.contains(.titled) {
            window.titlebarAppearsTransparent = false
        }
    }
}
