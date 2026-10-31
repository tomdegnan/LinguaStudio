import SwiftUI

/// General preferences panel (sheet). Labels follow AppSettings.uiLanguage.
struct GeneralSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: Store

    var body: some View {
        Form {
            Section(L10n.t("settings.section.language")) {
                Picker(L10n.t("settings.language"), selection: Binding(
                    get: { settings.uiLanguage },
                    set: { newValue in
                        // Let the popup dismiss before ContentView remounts on
                        // localeToken — avoids nesting toolbar layout in the
                        // menu tracking runloop (also a crash vector).
                        DispatchQueue.main.async {
                            settings.uiLanguage = newValue
                        }
                    }
                )) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
            }

            Section(L10n.t("settings.section.font")) {
                Picker(L10n.t("settings.font"), selection: $settings.fontFamily) {
                    ForEach(AppSettings.fontChoiceIDs, id: \.self) { id in
                        Text(AppSettings.fontLabel(for: id)).tag(id)
                    }
                }
                HStack {
                    Text(L10n.t("settings.fontSize"))
                    Slider(value: $settings.fontSize, in: 11...20, step: 1)
                    Text("\(Int(settings.fontSize)) pt")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }

            Section(L10n.t("settings.section.grid")) {
                Toggle(L10n.t("settings.rowFollowsFont"), isOn: $settings.rowHeightFollowsFont)
                if !settings.rowHeightFollowsFont {
                    HStack {
                        Text(L10n.t("settings.fixedRowHeight"))
                        Slider(value: $settings.fixedRowHeight, in: 48...160, step: 4)
                        Text("\(Int(settings.fixedRowHeight))")
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                } else {
                    Text(L10n.tf("settings.currentRowHeight", Int(settings.resolvedRowHeight)))
                        .foregroundStyle(.secondary)
                }
            }

            Section(L10n.t("settings.section.tags")) {
                Toggle(L10n.t("settings.showTags"), isOn: Binding(
                    get: { settings.showTags },
                    set: { settings.showTags = $0; store.showTags = $0 }
                ))
                Picker(L10n.t("settings.tagStyle"), selection: Binding(
                    get: { settings.tagStyle },
                    set: { settings.tagStyle = $0; store.tagStyle = $0 }
                )) {
                    ForEach(TagDisplayStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .disabled(!settings.showTags)
                Toggle(L10n.t("settings.showInvisibles"), isOn: Binding(
                    get: { settings.showInvisibles },
                    set: { settings.showInvisibles = $0; store.showInvisibles = $0 }
                ))
                Toggle(L10n.t("settings.trackingDefault"), isOn: $settings.trackingDefault)
                Toggle(L10n.t("settings.showHistory"), isOn: Binding(
                    get: { settings.showHistoryPanel },
                    set: { settings.showHistoryPanel = $0; store.showHistory = $0 }
                ))
            }

            Section(L10n.t("settings.section.appearance")) {
                Picker(L10n.t("settings.theme"), selection: Binding(
                    get: { settings.appearance },
                    set: { settings.appearance = $0 }
                )) {
                    ForEach(AppAppearance.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            }

            Section(L10n.t("settings.section.editing")) {
                Toggle(L10n.t("settings.confirmNext"), isOn: $settings.confirmAdvancesToNext)
                HStack {
                    Text(L10n.t("settings.maxHistory"))
                    Stepper(value: Binding(
                        get: { settings.maxHistorySteps },
                        set: {
                            settings.maxHistorySteps = $0
                            store.applyHistoryDepth($0)
                        }
                    ), in: 10...500, step: 10) {
                        Text("\(settings.maxHistorySteps)")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }

            Section {
                Button(L10n.t("settings.reset")) {
                    settings.resetToDefaults()
                    store.applySettingsDefaults(from: settings)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.bottom)
        // No .id(localeToken): remounting this form while the parent toolbar
        // rewrites labels caused NSToolbar layout crashes on language switch.
    }
}
