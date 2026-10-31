import SwiftUI
import AppKit
#if canImport(LinguaCore)
import LinguaCore
#endif


/// One-shot `.iconOnly` after locale remount. Never mutate toolbar during updates.
private struct ToolbarIconAndLabelConfigurer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        for delay in [0.0, 0.1, 0.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                Self.apply(from: view)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private static func apply(from view: NSView) {
        guard let toolbar = view.window?.toolbar else { return }
        if toolbar.displayMode != .iconOnly {
            toolbar.displayMode = .iconOnly
        }
        toolbar.sizeMode = .regular
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
    }
}


/// Slightly larger SF Symbol for the window toolbar (flat icon-only chrome).
private func toolbarIcon(_ name: String) -> some View {
    Image(systemName: name)
        .imageScale(.large)
        .font(.system(size: 15, weight: .regular))
}

struct ContentView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            filterAccessoryBar
            if store.reviewMode {
                reviewBar
            }
            if store.regexInvalid {
                Text(L10n.t("search.regexInvalid"))
                    .foregroundStyle(.red)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.08))
            }
            HSplitView {
                segmentTable
                if store.showHistory {
                    historyPanel
                }
            }
            Divider()
            statusBar
        }
        .frame(minWidth: 1000, minHeight: 640)
        .background(KeyMonitor(store: store))
        .toolbar { mainToolbar }
        .background(ToolbarIconAndLabelConfigurer())
        .onAppear { settings.applyAppearance() }
        .onChange(of: store.showReplaceSheet) { show in
            guard show else { return }
            openWindow(id: "replace")
            // Reset so ⌘⇧H can open again after closing.
            store.showReplaceSheet = false
        }
        // Remount root view on language change (window stays) — avoids NSToolbar
        // crash from in-place title rewrites. Icon-only ControlGroups stay flat.
        .id(settings.localeToken)
        .alert(
            L10n.t("alert.errorTitle"),
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button(L10n.t("alert.ok")) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .alert(
            L10n.t("alert.infoTitle"),
            isPresented: Binding(
                get: { store.infoMessage != nil },
                set: { if !$0 { store.infoMessage = nil } }
            )
        ) {
            Button(L10n.t("alert.ok")) { store.infoMessage = nil }
        } message: {
            Text(store.infoMessage ?? "")
        }
        .sheet(isPresented: $store.showSettings) {
            VStack(spacing: 0) {
                HStack {
                    Text(L10n.t("settings.title"))
                        .font(.headline)
                    Spacer()
                    Button(L10n.t("settings.done")) { store.showSettings = false }
                        .keyboardShortcut(.defaultAction)
                }
                .padding()
                Divider()
                GeneralSettingsView()
                    .environmentObject(settings)
                    .environmentObject(store)
            }
            .frame(width: 520, height: 560)
        }
    }

    // MARK: - Native toolbar + filter accessory

    /// Flat horizontal icon toolbar (no ControlGroup / no captions).
    /// ControlGroup capsules were stretching vertically over the filter bar.
    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { store.open() } label: {
                toolbarIcon("folder")
            }
            .help(L10n.t("toolbar.open"))

            Button { store.save() } label: {
                toolbarIcon("square.and.arrow.down")
            }
            .keyboardShortcut("s")
            .help(L10n.t("toolbar.save"))

            Button { store.saveAs() } label: {
                toolbarIcon("square.and.arrow.down.on.square")
            }
            .help(L10n.t("toolbar.saveAs"))
        }

        ToolbarItemGroup(placement: .principal) {
            Button { store.confirmAndNext() } label: {
                toolbarIcon("checkmark.circle")
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(store.selected == nil || store.reviewMode)
            .help(L10n.t("toolbar.confirmNext") + " ⌘↩")

            Button { store.toggleLock() } label: {
                toolbarIcon("lock")
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(store.selected == nil)
            .help(L10n.t("toolbar.lock") + " ⌘L")

            Toggle(isOn: Binding(
                get: { store.reviewMode },
                set: { store.setReviewMode($0) }
            )) {
                toolbarIcon("checkmark.shield")
            }
            .toggleStyle(.button)
            .help(L10n.t("toolbar.review"))
        }

        ToolbarItemGroup(placement: .automatic) {
            Button { store.applyFormat(.bold) } label: {
                toolbarIcon("bold")
            }
            .help(L10n.t("toolbar.bold.help"))
            .disabled(store.editingID == nil || store.reviewMode)

            Button { store.applyFormat(.italic) } label: {
                toolbarIcon("italic")
            }
            .help(L10n.t("toolbar.italic.help"))
            .disabled(store.editingID == nil || store.reviewMode)

            Button { store.applyFormat(.underline) } label: {
                toolbarIcon("underline")
            }
            .help(L10n.t("toolbar.underline.help"))
            .disabled(store.editingID == nil || store.reviewMode)

            Button { store.applyFormat(.superscript) } label: {
                toolbarIcon("textformat.superscript")
            }
            .help(L10n.t("toolbar.superscript.help"))
            .disabled(store.editingID == nil || store.reviewMode)

            Button { store.applyFormat(.subscript) } label: {
                toolbarIcon("textformat.subscript")
            }
            .help(L10n.t("toolbar.subscript.help"))
            .disabled(store.editingID == nil || store.reviewMode)
        }

        ToolbarItem(placement: .automatic) {
            Menu {
                Toggle(isOn: Binding(
                    get: { store.showTags },
                    set: { store.showTags = $0; settings.showTags = $0 }
                )) {
                    Label(L10n.t("toolbar.showTags"), systemImage: "tag")
                }
                Picker(selection: Binding(
                    get: { store.tagStyle },
                    set: { store.tagStyle = $0; settings.tagStyle = $0 }
                )) {
                    ForEach(TagDisplayStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                } label: {
                    Text(L10n.t("toolbar.tagStyle"))
                }
                .disabled(!store.showTags)

                Toggle(isOn: Binding(
                    get: { store.showInvisibles },
                    set: { store.showInvisibles = $0; settings.showInvisibles = $0 }
                )) {
                    Label(L10n.t("toolbar.invisibles"), systemImage: "space")
                }

                Divider()

                Toggle(isOn: Binding(
                    get: { store.tracking },
                    set: { store.setTracking($0) }
                )) {
                    Label(L10n.t("toolbar.tracking"), systemImage: "pencil.and.outline")
                }
                .disabled(store.reviewMode)
            } label: {
                toolbarIcon("eye")
            }
            .help(L10n.t("chrome.display"))
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button { store.openReplacePanel() } label: {
                toolbarIcon("arrow.triangle.2.circlepath")
            }
            .help(L10n.t("replace.open.help"))

            Button {
                store.showHistory.toggle()
                settings.showHistoryPanel = store.showHistory
            } label: {
                toolbarIcon("sidebar.trailing")
            }
            .help(store.showHistory ? L10n.t("toolbar.hideHistory") : L10n.t("toolbar.showHistory"))

            Button { store.showSettings = true } label: {
                toolbarIcon("gearshape")
            }
            .help(L10n.t("toolbar.settings.help"))
        }
    }

    /// Single accessory strip under the window toolbar (Finder/Xcode-style filter bar).
    private var filterAccessoryBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(.secondary)
                .help(L10n.t("chrome.find"))

            TextField(L10n.t("search.source"), text: $store.sourceQuery)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120, idealWidth: 160, maxWidth: 220)

            TextField(L10n.t("search.target"), text: $store.targetQuery)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 140, idealWidth: 200, maxWidth: 280)

            ControlGroup {
                Toggle(L10n.t("search.case"), isOn: $store.caseSensitive)
                    .toggleStyle(.button)
                    .help(L10n.t("search.case.help"))
                Toggle(L10n.t("search.word"), isOn: $store.wholeWord)
                    .toggleStyle(.button)
                    .help(L10n.t("search.word.help"))
                Toggle(L10n.t("search.regex"), isOn: $store.useRegex)
                    .toggleStyle(.button)
                    .help(L10n.t("search.regex.help"))
            }

            Divider().frame(height: 16)

            Button {
                store.findPrevious()
            } label: {
                Image(systemName: "chevron.up")
            }
            .help(L10n.t("search.prev") + " ⌘⇧G")

            Button {
                store.findNext()
            } label: {
                Image(systemName: "chevron.down")
            }
            .help(L10n.t("search.next") + " ⌘G")

            Text(store.matchCount > 0
                 ? "\(store.matchIndex) / \(store.matchCount)"
                 : "0 / \(store.rows.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 52, alignment: .leading)

            Divider().frame(height: 16)

            Picker(selection: Binding(
                get: { store.statusFilter },
                set: { store.applyStatusFilter($0) }
            )) {
                ForEach(Store.statusFilterKeys, id: \.self) { key in
                    Text(Store.statusFilterLabel(key)).tag(key)
                }
            } label: {
                Text(L10n.t("search.status"))
            }
            .labelsHidden()
            .frame(minWidth: 110, idealWidth: 130)
            .help(L10n.t("search.status"))

            Text(L10n.tf("search.filtered", store.filteredRows.count, store.rows.count))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Button {
                store.refreshFilter()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(!store.filterHasHeldRows)
            .help(L10n.t("search.refresh.help"))

            Spacer(minLength: 0)
        }
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// Thin vertical rule. Always pass an explicit height — bare `Rectangle()`
    /// expands vertically and blew the column header into a huge gray void.
    private func columnSpine(height: CGFloat) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.45))
            .frame(width: 1.5, height: height)
            .padding(.horizontal, 5)
            .accessibilityHidden(true)
    }

    private static let columnHeaderHeight: CGFloat = 32


    private var reviewBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(.orange)
            Text(L10n.t("review.title"))
                .font(.headline)
                .foregroundStyle(.orange)
            Text(L10n.t("review.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Divider().frame(height: 18)
            Button(L10n.t("review.prev"), systemImage: "chevron.up") {
                store.goToPending(next: false)
            }
            .help("⌘↑")
            Button(L10n.t("review.next"), systemImage: "chevron.down") {
                store.goToPending(next: true)
            }
            .help("⌘↓")
            Button(L10n.t("review.accept")) { store.review(accept: true) }
                .disabled(!store.selectedHasPending)
            Button(L10n.t("review.reject")) { store.review(accept: false) }
                .disabled(!store.selectedHasPending)
            Button(L10n.t("review.acceptAll")) { store.reviewAll(accept: true) }
                .disabled(store.pendingKeysInScope.isEmpty)
            Button(L10n.t("review.rejectAll")) { store.reviewAll(accept: false) }
                .disabled(store.pendingKeysInScope.isEmpty)
            Spacer(minLength: 0)
            Text(L10n.tf("review.pending", store.pendingKeysInScope.count))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.12))
    }


    // MARK: - Table

    private var segmentTable: some View {
        VStack(spacing: 0) {
            // Hard-capped strip — never let header flex into the scroll area.
            HStack(spacing: 0) {
                Text("#").frame(width: 40, alignment: .leading)
                Text(L10n.t("grid.source"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                columnSpine(height: Self.columnHeaderHeight - 10)
                Text(L10n.t("grid.status"))
                    .frame(width: 56, alignment: .center)
                Text(L10n.t("grid.target"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 8)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: Self.columnHeaderHeight)
            .frame(maxHeight: Self.columnHeaderHeight)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color(nsColor: .separatorColor).opacity(0.35))
            .clipped()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.filteredRows) { row in
                        segmentRow(row)
                            .id(row.id.description)
                    }
                }
                .id(settings.typographyToken)
            }
            .overlay {
                if store.rows.isEmpty {
                    emptyState(
                        title: L10n.t("grid.emptyOpen"),
                        systemImage: "doc.text",
                        subtitle: L10n.t("grid.emptyOpen.sub")
                    )
                } else if store.filteredRows.isEmpty {
                    emptyState(
                        title: L10n.t("grid.emptyFilter"),
                        systemImage: "magnifyingglass",
                        subtitle: L10n.t("grid.emptyFilter.sub")
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func segmentRow(_ row: SegmentRow) -> some View {
        let absoluteIndex =
            (store.rows.firstIndex(where: { $0.id == row.id }) ?? 0) + 1
        let isSelected = store.selected == row.id
        let pending = row.hasPendingRevisions

        HStack(alignment: .top, spacing: 0) {
            Text("\(absoluteIndex)")
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .topLeading)
                .padding(.top, 4)

            // Source: read-only, fixed height, scroll/clip if overflow
            cellScroll {
                Group {
                    if let node = store.document?.sourceNodes[row.id] {
                        displayXML(
                            node,
                            showTags: store.showTags,
                            tagStyle: store.tagStyle,
                            showInvisibles: store.showInvisibles,
                            formats: store.formatting
                        )
                    } else {
                        Text(row.source)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .textSelection(.enabled)
            }
            .padding(.trailing, 6)

            // Clear source | target spine (status sits in the gutter).
            columnSpine(height: SegmentGridMetrics.rowHeight - 8)

            statusCell(row)
                .frame(width: 56, alignment: .top)
                .padding(.top, 4)

            // Target: read-only display OR the single shared live editor when selected
            targetCell(row)
                .padding(.leading, 8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(height: SegmentGridMetrics.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground(isSelected: isSelected, pending: pending))
        .contentShape(Rectangle())
        // TextSelection / ScrollView can eat plain onTapGesture; simultaneous
        // ensures click always chooses this segment and moves the shared editor.
        .simultaneousGesture(TapGesture().onEnded { _ in handleTap(row) })
        .overlay(alignment: .bottom) { Divider() }
        .overlay(alignment: .leading) {
            if store.reviewMode && pending {
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 3)
            }
        }
        .clipped()
    }

    /// Scrollable interior for a fixed-height source/target display cell.
    @ViewBuilder
    private func cellScroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            content()
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func rowBackground(isSelected: Bool, pending: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(0.14)
        }
        if store.reviewMode && pending {
            return Color.orange.opacity(0.08)
        }
        if pending {
            return Color.yellow.opacity(0.06)
        }
        return Color.clear
    }

    private func statusCell(_ row: SegmentRow) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(row.status == .draft ? Color.blue : Color.green)
                .frame(width: 9, height: 9)
                .help(row.status.rawValue)
            if row.hasPendingRevisions {
                Text(L10n.t("grid.revision"))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.orange.opacity(0.25))
                    .foregroundStyle(.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .help(L10n.t("grid.revision.help"))
            }
        }
    }

    @ViewBuilder
    private func targetCell(_ row: SegmentRow) -> some View {
        // Only the selected editing row mounts the ONE shared NSTextView.
        // Every other row is a read-only SwiftUI display of the target XML.
        if store.editingID == row.id,
           row.isEditable,
           !store.reviewMode,
           let plan = store.document?.plan(for: row.id) {
            RichSegmentEditor(
                segmentID: row.id,
                session: store.editSession,
                plan: plan,
                draft: store.draft,
                showTags: store.showTags,
                tagStyle: store.tagStyle,
                tracking: store.tracking,
                showInvisibles: store.showInvisibles,
                formats: store.formatting,
                onChange: { value in
                    // Guard: never let a stale callback write the wrong segment.
                    if store.editingID == row.id {
                        store.noteEditorChange(value)
                    }
                },
                onConfirm: { store.confirmAndNext() },
                onCancel: { store.cancelEdit() },
                onLock: { store.toggleLock() },
                onUndo: { store.undoLatest() },
                onRedo: { store.redoLatest() },
                onFormat: { store.applyFormat($0) },
                onAcceptRevision: { store.review(accept: true) },
                onRejectRevision: { store.review(accept: false) },
                onAttach: { view in store.activeEditor = view },
                onRenderError: { message in store.errorMessage = message },
                pendingDraftSelection: store.pendingDraftSelection,
                onConsumePendingDraftSelection: { store.pendingDraftSelection = nil }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            cellScroll {
                HStack(alignment: .top, spacing: 6) {
                    Group {
                        if let node = store.document?.targetNodes[row.id] {
                            displayXML(
                                node,
                                showTags: store.showTags,
                                tagStyle: store.tagStyle,
                                showInvisibles: store.showInvisibles,
                                formats: store.formatting
                            )
                        } else {
                            Text(row.target.isEmpty ? L10n.t("grid.clickEdit") : row.target)
                                .foregroundStyle(row.target.isEmpty ? .secondary : .primary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    // No .textSelection here — it steals the click and leaves
                    // another row highlighted while this cell shows a ghost selection.
                    // Editing uses the shared NSTextView after choose().

                    if row.isLocked {
                        Label(L10n.t("grid.locked"), systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if row.isUntranslatable {
                        Label(L10n.t("grid.readonly"), systemImage: "doc.badge.ellipsis")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .contentShape(Rectangle())
        }
    }

    private func handleTap(_ row: SegmentRow) {
        // Single click selects; Store.choose flushes prior draft and opens inline editor.
        if store.selected != row.id {
            store.choose(row.id)
            return
        }
        // Same-row click: remind about review / lock / read-only; otherwise re-enter edit.
        if store.reviewMode {
            if row.hasPendingRevisions {
                store.infoMessage = L10n.t("msg.reviewTap")
            }
        } else if row.isLocked {
            store.errorMessage = L10n.t("msg.locked")
        } else if row.isUntranslatable {
            store.errorMessage = L10n.t("msg.untranslatable")
        } else if store.editingID != row.id {
            store.beginEditing(row.id)
        }
    }

    // MARK: - History / status

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.t("history.title")).font(.headline)
                Spacer()
                Button {
                    store.showHistory = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }
            HStack {
                Button(L10n.t("history.undo")) { store.undoLatest() }
                    .disabled(!store.canUndo)
                    .help("⌘Z")
                Button(L10n.t("history.redo")) { store.redoLatest() }
                    .disabled(!store.canRedo)
                    .help("⌘⇧Z")
            }
            Text(L10n.t("history.caption"))
                .font(.caption)
                .foregroundStyle(.secondary)
            List {
                ForEach(Array(store.historyEntries.enumerated()), id: \.element.id) {
                    index,
                    entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(
                                index < store.historyPosition ? .primary : .secondary
                            )
                        if !entry.detail.isEmpty {
                            Text(entry.detail)
                                .font(.caption)
                                .foregroundStyle(
                                    index < store.historyPosition
                                        ? Color.primary.opacity(0.85) : .secondary
                                )
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(entry.date, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Button(
                            index < store.historyPosition
                                ? L10n.t("history.jumpBefore")
                                : L10n.t("history.jumpAfter")
                        ) {
                            store.restoreHistory(
                                index < store.historyPosition ? index : index + 1
                            )
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.sidebar)
        }
        .padding(10)
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
    }

    private var statusBar: some View {
        HStack {
            Text(store.dirty || store.editingID != nil ? L10n.t("toolbar.unsaved") : L10n.t("toolbar.saved"))
                .foregroundStyle(store.dirty || store.editingID != nil ? Color.orange : Color.secondary)
            Text("·").foregroundStyle(.quaternary)
            if store.reviewMode {
                Text(L10n.t("status.reviewHint"))
                    .foregroundStyle(.orange)
            } else if store.editingID != nil {
                Button(L10n.t("status.cancelEdit")) { store.cancelEdit() }
                    .keyboardShortcut(.escape, modifiers: [])
                Text(L10n.t("status.editHint"))
                    .foregroundStyle(.secondary)
            }
            Text(store.fileURL?.lastPathComponent ?? L10n.t("status.untitled"))
            Spacer()
            Text(
                L10n.tf("status.confirmedCount", store.rows.filter { $0.status == .confirmed }.count, store.rows.count)
            )
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(8)
    }

    private func emptyState(title: String, systemImage: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(subtitle).foregroundStyle(.secondary)
        }
    }
}

// MARK: - F9 / Cmd+Arrow key monitor (Review navigation)

/// Invisible view that installs a local key monitor for shortcuts SwiftUI Commands
/// cannot always express: F9 / Shift+F9 (pending), ⌥↑ / ⌥↓ (filtered segment nav).
private struct KeyMonitor: NSViewRepresentable {
    let store: Store

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(store: store)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.store = store
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var store: Store?
        private var monitor: Any?

        func install(store: Store) {
            self.store = store
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let store = self.store else { return event }
                return self.handle(event, store: store) ? nil : event
            }
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        /// Returns true if the event was consumed.
        /// F9 / Shift+F9 — pending nav. ⌥↑ / ⌥↓ — prev/next filtered segment
        /// (bare arrows stay with the text view while editing).
        private func handle(_ event: NSEvent, store: Store) -> Bool {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Ignore capsLock/fn when comparing modifiers.
            let chords = flags.intersection([.command, .option, .control, .shift])
            // F9 = next pending, Shift+F9 = previous (Studio-style; needs Fn on some keyboards).
            if event.keyCode == 101 { // F9
                Task { @MainActor in
                    store.goToPending(next: !flags.contains(.shift))
                }
                return true
            }
            // Shift+F3 — case cycle (also handled in SegmentTextView while editing).
            if event.keyCode == 99, chords == .shift {
                Task { @MainActor in store.cycleCase() }
                return true
            }
            // Option+Up / Option+Down: move selection among filtered rows.
            // Chosen over bare arrows so NSTextView keeps ↑/↓ while typing in the inline editor.
            let onlyOption = chords == .option
            if onlyOption && (event.keyCode == 126 || event.keyCode == 125) { // up / down
                Task { @MainActor in
                    store.selectAdjacentFiltered(next: event.keyCode == 125)
                }
                return true
            }
            // ⌘Z / ⌘⇧Z → session history (also handled in SegmentTextView + Edit menu).
            if event.charactersIgnoringModifiers?.lowercased() == "z" {
                if chords == [.command, .shift] {
                    Task { @MainActor in store.redoLatest() }
                    return true
                }
                if chords == .command {
                    Task { @MainActor in store.undoLatest() }
                    return true
                }
            }
            return false
        }
    }
}
