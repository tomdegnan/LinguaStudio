import Foundation

/// App UI language: Chinese or English (never mixed bilingual labels).
enum AppLanguage: String, CaseIterable, Identifiable {
    case zh
    case en

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .zh: return "中文"
        case .en: return "English"
        }
    }
}

/// Simple key → (zh, en) lookup. Reads live language from AppSettings.
enum L10n {
    static var language: AppLanguage { AppSettings.shared.uiLanguage }

    static func t(_ key: String) -> String {
        guard let pair = table[key] else { return key }
        return language == .en ? pair.en : pair.zh
    }

    static func tf(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), locale: Locale(identifier: language == .en ? "en_US" : "zh_CN"), arguments: args)
    }

    private struct Pair { let zh: String; let en: String }

    private static let table: [String: Pair] = [
        // Language / settings chrome
        "settings.title": .init(zh: "通用设置", en: "General Settings"),
        "settings.done": .init(zh: "完成", en: "Done"),
        "settings.language": .init(zh: "界面语言", en: "UI Language"),
        "settings.section.language": .init(zh: "语言", en: "Language"),
        "settings.section.font": .init(zh: "字体", en: "Typography"),
        "settings.font": .init(zh: "字体", en: "Font"),
        "settings.fontSize": .init(zh: "字号", en: "Size"),
        "settings.section.grid": .init(zh: "句段网格", en: "Segment Grid"),
        "settings.rowFollowsFont": .init(zh: "行高随字号", en: "Row height follows font"),
        "settings.fixedRowHeight": .init(zh: "固定行高", en: "Fixed height"),
        "settings.currentRowHeight": .init(zh: "当前行高：%d pt", en: "Current height: %d pt"),
        "settings.section.tags": .init(zh: "标签与显示", en: "Tags & Display"),
        "settings.showTags": .init(zh: "默认显示标签", en: "Show tags by default"),
        "settings.tagStyle": .init(zh: "默认标签样式", en: "Default tag style"),
        "settings.showInvisibles": .init(zh: "默认显示非打印字符", en: "Show nonprinting by default"),
        "settings.trackingDefault": .init(zh: "打开文件时默认记录修订", en: "Track changes by default"),
        "settings.showHistory": .init(zh: "显示修改记录侧栏", en: "Show history sidebar"),
        "settings.section.appearance": .init(zh: "外观", en: "Appearance"),
        "settings.theme": .init(zh: "主题", en: "Theme"),
        "settings.section.editing": .init(zh: "编辑行为", en: "Editing"),
        "settings.confirmNext": .init(zh: "确认后跳转下一句（⌘↩）", en: "Confirm advances to next (⌘↩)"),
        "settings.maxHistory": .init(zh: "历史步数上限", en: "Max history steps"),
        "settings.reset": .init(zh: "恢复默认", en: "Reset to Defaults"),
        "appearance.system": .init(zh: "跟随系统", en: "Follow System"),
        "appearance.light": .init(zh: "浅色", en: "Light"),
        "appearance.dark": .init(zh: "深色", en: "Dark"),
        "font.system": .init(zh: "系统字体", en: "System Font"),
        "font.pingfang": .init(zh: "苹方", en: "PingFang SC"),
        "font.songti": .init(zh: "宋体", en: "Songti SC"),
        "tagStyle.full": .init(zh: "完整标签", en: "Full tags"),
        "tagStyle.short": .init(zh: "简短标签", en: "Short tags"),

        // Chrome section labels
        "chrome.file": .init(zh: "文件", en: "File"),
        "chrome.edit": .init(zh: "编辑", en: "Edit"),
        "chrome.display": .init(zh: "显示", en: "Display"),
        "chrome.find": .init(zh: "查找", en: "Find"),

        // Toolbar
        "toolbar.open": .init(zh: "打开", en: "Open"),
        "toolbar.save": .init(zh: "保存", en: "Save"),
        "toolbar.saveAs": .init(zh: "另存为…", en: "Save As…"),
        "toolbar.confirmNext": .init(zh: "确认并下一句", en: "Confirm & Next"),
        "toolbar.lock": .init(zh: "锁定 / 解锁", en: "Lock / Unlock"),
        "toolbar.review": .init(zh: "核对模式", en: "Review Mode"),
        "toolbar.settings": .init(zh: "设置", en: "Settings"),
        "toolbar.settings.help": .init(zh: "通用设置 ⌘,", en: "General Settings ⌘,"),
        "toolbar.hideHistory": .init(zh: "隐藏修改记录", en: "Hide History"),
        "toolbar.showHistory": .init(zh: "显示修改记录", en: "Show History"),
        "toolbar.unsaved": .init(zh: "未保存", en: "Unsaved"),
        "toolbar.saved": .init(zh: "已保存", en: "Saved"),
        "toolbar.showTags": .init(zh: "显示标签", en: "Show Tags"),
        "toolbar.tagStyle": .init(zh: "标签样式", en: "Tag Style"),
        "toolbar.tagStyle.help": .init(zh: "完整标签显示名称；简短标签仅显示 → ←", en: "Full tags show names; short tags show → ← only"),
        "toolbar.invisibles": .init(zh: "非打印字符", en: "Nonprinting"),
        "toolbar.tracking": .init(zh: "记录修订", en: "Track Changes"),
        "toolbar.bold.help": .init(zh: "粗体 ⌘B", en: "Bold ⌘B"),
        "toolbar.italic.help": .init(zh: "斜体 ⌘I", en: "Italic ⌘I"),
        "toolbar.underline.help": .init(zh: "下划线 ⌘U", en: "Underline ⌘U"),
        "toolbar.superscript.help": .init(zh: "上标", en: "Superscript"),
        "toolbar.subscript.help": .init(zh: "下标", en: "Subscript"),
        "toolbar.acceptSeg": .init(zh: "接受本句修订", en: "Accept Segment Revisions"),
        "toolbar.rejectSeg": .init(zh: "拒绝本句修订", en: "Reject Segment Revisions"),
        // Short labels under toolbar icons (macOS icon+label density)
        "toolbar.short.open": .init(zh: "打开", en: "Open"),
        "toolbar.short.save": .init(zh: "保存", en: "Save"),
        "toolbar.short.saveAs": .init(zh: "另存为", en: "Save As"),
        "toolbar.short.confirm": .init(zh: "确认", en: "Confirm"),
        "toolbar.short.lock": .init(zh: "锁定", en: "Lock"),
        "toolbar.short.review": .init(zh: "核对", en: "Review"),
        "toolbar.short.display": .init(zh: "显示", en: "View"),
        "toolbar.short.replace": .init(zh: "替换", en: "Replace"),
        "toolbar.short.history": .init(zh: "记录", en: "History"),
        "toolbar.short.settings": .init(zh: "设置", en: "Settings"),
        "toolbar.short.bold": .init(zh: "粗体", en: "Bold"),
        "toolbar.short.italic": .init(zh: "斜体", en: "Italic"),
        "toolbar.short.underline": .init(zh: "下划线", en: "Under"),
        "toolbar.short.superscript": .init(zh: "上标", en: "Super"),
        "toolbar.short.subscript": .init(zh: "下标", en: "Sub"),
        "toolbar.group.file": .init(zh: "文件", en: "File"),
        "toolbar.group.workflow": .init(zh: "流程", en: "Flow"),
        "toolbar.group.format": .init(zh: "格式", en: "Format"),
        "toolbar.group.view": .init(zh: "显示", en: "View"),
        "toolbar.group.utils": .init(zh: "工具", en: "Tools"),


        // Review bar
        "ctx.acceptRevision": .init(zh: "接受修订", en: "Accept Revision"),
        "ctx.rejectRevision": .init(zh: "拒绝修订", en: "Reject Revision"),
        "review.title": .init(zh: "核对模式", en: "Review Mode"),
        "review.hint": .init(zh: "· 仅处理待审修订（接受/拒绝）；自由编辑需退出", en: "· Accept/reject pending revisions only; leave Review to edit freely"),
        "review.prev": .init(zh: "上一处修订", en: "Previous Revision"),
        "review.next": .init(zh: "下一处修订", en: "Next Revision"),
        "review.accept": .init(zh: "接受本句", en: "Accept"),
        "review.reject": .init(zh: "拒绝本句", en: "Reject"),
        "review.acceptAll": .init(zh: "全部接受…", en: "Accept All…"),
        "review.rejectAll": .init(zh: "全部拒绝…", en: "Reject All…"),
        "review.pending": .init(zh: "待审 %d", en: "Pending %d"),

        // Search
        "search.source": .init(zh: "搜索原文", en: "Search source"),
        "search.target": .init(zh: "搜索译文", en: "Search target"),
        "replace.title": .init(zh: "替换", en: "Replace"),
        "replace.open": .init(zh: "替换…", en: "Replace…"),
        "replace.open.help": .init(zh: "打开替换窗口 ⌘⇧H", en: "Open Replace window ⌘⇧H"),
        "replace.find": .init(zh: "查找内容", en: "Find"),
        "replace.with": .init(zh: "替换为", en: "Replace with"),
        "replace.done": .init(zh: "完成", en: "Done"),
        "menu.openReplace": .init(zh: "替换…", en: "Replace…"),
        "search.replace": .init(zh: "替换为", en: "Replace with"),
        "search.case": .init(zh: "大小写", en: "Case"),
        "search.case.help": .init(zh: "区分大小写", en: "Case sensitive"),
        "search.word": .init(zh: "词", en: "Word"),
        "search.word.help": .init(zh: "全词匹配", en: "Whole word"),
        "search.regex": .init(zh: "正则", en: "Regex"),
        "search.regex.help": .init(zh: "正则表达式", en: "Regular expression"),
        "search.status": .init(zh: "状态", en: "Status"),
        "search.prev": .init(zh: "上一个", en: "Previous"),
        "search.next": .init(zh: "下一个", en: "Next"),
        "search.replaceOne": .init(zh: "替换", en: "Replace"),
        "search.replaceAll": .init(zh: "全部替换…", en: "Replace All…"),
        "search.replace.help": .init(zh: "直接在译文中查找并替换下一处（不依赖筛选；仅纯文本空隙）", en: "Find and replace the next match in targets directly (no filter; plain gaps only)"),
        "search.replaceAll.help": .init(zh: "在全部句段译文中直接替换（不依赖筛选；跳过跨标签句段）", en: "Replace across all targets directly (no filter; skip cross-tag segments)"),
        "search.filtered": .init(zh: "筛选 %d / %d 段", en: "Filtered %d / %d"),
        "search.refresh": .init(zh: "刷新", en: "Refresh"),
        "search.refresh.help": .init(zh: "按当前筛选条件重新过滤（清除确认后仍显示的句段）", en: "Re-apply the current filter (clear rows kept after confirm)"),
        "search.regexInvalid": .init(zh: "正则表达式无效，请检查输入。", en: "Invalid regular expression."),

        // Status filter keys (stable)
        "status.all": .init(zh: "全部", en: "All"),
        "status.untranslated": .init(zh: "未翻译", en: "Untranslated"),
        "status.draft": .init(zh: "草稿", en: "Draft"),
        "status.confirmed": .init(zh: "已确认", en: "Confirmed"),
        "status.revisions": .init(zh: "有修订", en: "Has Revisions"),
        "status.locked": .init(zh: "已锁定", en: "Locked"),

        // Grid
        "grid.source": .init(zh: "原文", en: "Source"),
        "grid.status": .init(zh: "状态", en: "Status"),
        "grid.target": .init(zh: "译文", en: "Target"),
        "grid.emptyOpen": .init(zh: "打开 SDLXLIFF 开始翻译", en: "Open an SDLXLIFF to start translating"),
        "grid.emptyOpen.sub": .init(zh: "打开 UTF-8 的 .sdlxliff 文件", en: "Open a UTF-8 .sdlxliff file"),
        "grid.emptyFilter": .init(zh: "没有匹配的段落", en: "No matching segments"),
        "grid.emptyFilter.sub": .init(zh: "没有匹配的句段", en: "No matching segments"),
        "grid.revision": .init(zh: "修订", en: "Rev"),
        "grid.revision.help": .init(zh: "含待审 SDL 修订", en: "Pending SDL revisions"),
        "grid.clickEdit": .init(zh: "点击编辑译文", en: "Click to edit target"),
        "grid.locked": .init(zh: "已锁定", en: "Locked"),
        "grid.readonly": .init(zh: "只读", en: "Read-only"),

        // History
        "history.title": .init(zh: "修改记录", en: "History"),
        "history.undo": .init(zh: "撤回", en: "Undo"),
        "history.redo": .init(zh: "重做", en: "Redo"),
        "history.caption": .init(zh: "本次打开后的修改（含原文→新文预览，会话撤销）", en: "Session changes with before→after preview (session undo)"),
        "history.jumpBefore": .init(zh: "撤回到此修改之前", en: "Undo to before this change"),
        "history.jumpAfter": .init(zh: "恢复到此修改之后", en: "Redo to after this change"),

        // Status bar
        "status.reviewHint": .init(zh: "核对模式开启 · ⌘↓/⌘↑ 或 F9/⇧F9 跳转待审 · ⌘⇧A 接受 · ⌘⇧R 拒绝", en: "Review on · ⌘↓/⌘↑ or F9/⇧F9 pending · ⌘⇧A accept · ⌘⇧R reject"),
        "status.cancelEdit": .init(zh: "取消本次编辑", en: "Cancel Edit"),
        "status.editHint": .init(zh: "蓝色标签受保护；⌘↩ 确认并下一句 · ⌥↑/⌥↓ 切换句段 · 切换句段时自动提交", en: "Blue tags protected; ⌘↩ confirm & next · ⌥↑/⌥↓ change segment · auto-commit on switch"),
        "status.untitled": .init(zh: "未命名项目", en: "Untitled Project"),
        "status.confirmedCount": .init(zh: "已确认 %d / %d", en: "Confirmed %d / %d"),

        // Alerts common
        "alert.ok": .init(zh: "好", en: "OK"),
        "alert.cancel": .init(zh: "取消", en: "Cancel"),
        "alert.errorTitle": .init(zh: "操作提示", en: "Notice"),
        "alert.infoTitle": .init(zh: "提示", en: "Info"),

        // Menus
        "menu.settings": .init(zh: "设置…", en: "Settings…"),
        "menu.undo": .init(zh: "撤回", en: "Undo"),
        "menu.redo": .init(zh: "重做", en: "Redo"),
        "menu.cycleCase": .init(zh: "切换大小写", en: "Cycle Case"),
        "menu.upperCase": .init(zh: "全部大写", en: "UPPERCASE"),
        "menu.lowerCase": .init(zh: "全部小写", en: "lowercase"),
        "menu.capitalizedCase": .init(zh: "首字母大写", en: "Capitalize"),
        "menu.bold": .init(zh: "粗体", en: "Bold"),
        "menu.italic": .init(zh: "斜体", en: "Italic"),
        "menu.underline": .init(zh: "下划线", en: "Underline"),
        "menu.superscript": .init(zh: "上标", en: "Superscript"),
        "menu.subscript": .init(zh: "下标", en: "Subscript"),
        "menu.findNext": .init(zh: "查找下一个", en: "Find Next"),
        "menu.findPrev": .init(zh: "查找上一个", en: "Find Previous"),
        "menu.replace": .init(zh: "替换", en: "Replace"),
        "menu.replaceAll": .init(zh: "全部替换…", en: "Replace All…"),
        "menu.review": .init(zh: "核对", en: "Review"),
        "menu.enterReview": .init(zh: "进入核对模式", en: "Enter Review Mode"),
        "menu.exitReview": .init(zh: "退出核对模式", en: "Exit Review Mode"),
        "menu.nextPending": .init(zh: "下一处待审修订", en: "Next Pending Revision"),
        "menu.prevPending": .init(zh: "上一处待审修订", en: "Previous Pending Revision"),
        "menu.acceptSeg": .init(zh: "接受本句修订", en: "Accept Segment Revisions"),
        "menu.rejectSeg": .init(zh: "拒绝本句修订", en: "Reject Segment Revisions"),
        "menu.acceptAll": .init(zh: "接受全部待审…", en: "Accept All Pending…"),
        "menu.rejectAll": .init(zh: "拒绝全部待审…", en: "Reject All Pending…"),

        // Store messages
        "msg.unsavedTitle": .init(zh: "当前项目有未保存的更改", en: "Unsaved Changes"),
        "msg.unsavedBody": .init(zh: "打开其他文件前，请先保存。继续将丢失未保存的更改。", en: "Save before opening another file. Continuing will discard unsaved changes."),
        "msg.discardOpen": .init(zh: "放弃更改并打开", en: "Discard and Open"),
        "msg.noDocument": .init(zh: "没有打开的文档。", en: "No document open."),
        "msg.reviewEditTitle": .init(zh: "当前处于核对模式", en: "Review Mode Active"),
        "msg.reviewEditBody": .init(zh: "核对模式下不直接编辑译文。退出核对模式后再编辑？", en: "Free editing is disabled in Review mode. Leave Review to edit?"),
        "msg.leaveReviewEdit": .init(zh: "退出核对并编辑", en: "Leave Review & Edit"),
        "msg.noPending": .init(zh: "没有待审修订。", en: "No pending revisions."),
        "msg.acceptAllTitle": .init(zh: "接受全部待审修订？", en: "Accept all pending revisions?"),
        "msg.rejectAllTitle": .init(zh: "拒绝全部待审修订？", en: "Reject all pending revisions?"),
        "msg.acceptAllBody": .init(zh: "将对当前范围内 %d 个含修订的句段执行「接受」。", en: "Accept revisions in %d segment(s) in the current scope."),
        "msg.rejectAllBody": .init(zh: "将对当前范围内 %d 个含修订的句段执行「拒绝」。", en: "Reject revisions in %d segment(s) in the current scope."),
        "msg.acceptAllBtn": .init(zh: "接受全部", en: "Accept All"),
        "msg.rejectAllBtn": .init(zh: "拒绝全部", en: "Reject All"),
        "msg.acceptedCount": .init(zh: "已接受 %d 个句段的修订。", en: "Accepted revisions in %d segment(s)."),
        "msg.rejectedCount": .init(zh: "已拒绝 %d 个句段的修订。", en: "Rejected revisions in %d segment(s)."),
        "msg.noMatches": .init(zh: "没有匹配。", en: "No matches."),
        "msg.enterFind": .init(zh: "请先在替换窗口的「查找内容」中输入要查找的文本。", en: "Enter find text in the Replace panel."),
        "msg.regexInvalid": .init(zh: "正则表达式无效。", en: "Invalid regular expression."),
        "msg.replacedCount": .init(zh: "已替换 %d 处。", en: "Replaced %d."),
        "msg.replaceCrossTag": .init(zh: "替换会跨越受保护标签，已跳过本句。", en: "Replace would cross tags; skipped."),
        "msg.replaceLockedRevision": .init(zh: "匹配位于修订标记内。请开启「记录修订」后再替换，或先接受/拒绝修订。", en: "Match is inside a revision mark. Turn on Track Changes to replace, or accept/reject first."),
        "msg.noMatchSeg": .init(zh: "本句无匹配。", en: "No match in this segment."),
        "msg.replaceAllTitle": .init(zh: "全部替换？", en: "Replace All?"),
        "msg.replaceAllBody": .init(zh: "将在全部 %d 个句段译文中直接查找并替换（不依赖筛选）。仅修改纯文本空隙，不会改动标签；若匹配会跨标签则跳过该句。", en: "Replace across all %d target segment(s) directly (no filter). Only plain gaps are changed; segments where a match would cross tags are skipped."),
        "msg.replaceAllBtn": .init(zh: "全部替换", en: "Replace All"),
        "msg.replaceAllDone": .init(zh: "替换 %d 处（%d 句）；跳过跨标签 %d；其他跳过 %d。", en: "Replaced %d in %d seg(s); skipped cross-tag %d; other skipped %d."),
        "msg.openSegment": .init(zh: "请先打开句段编辑译文。", en: "Open a segment to edit the target."),
        "msg.formatReview": .init(zh: "核对模式下不能设置格式。", en: "Formatting is disabled in Review mode."),
        "msg.noEditor": .init(zh: "当前没有活动的编辑器。", en: "No active editor."),
        "msg.locked": .init(zh: "句段已锁定。按 ⌘L 可解锁。", en: "Segment locked. Press ⌘L to unlock."),
        "msg.untranslatable": .init(zh: "文件将此内容标记为不可翻译。", en: "Marked translate=no."),
        "msg.reviewTap": .init(zh: "核对模式：使用「接受本句 / 拒绝本句」处理修订，或退出核对后编辑。", en: "Review mode: Accept/Reject revisions, or leave Review to edit."),
        "msg.tagParse": .init(zh: "句段 %@ 标签无法解析，已按纯文本显示（内容未丢失）：%@", en: "Segment %@: tags could not be parsed; shown as plain text (content kept): %@"),
        "hist.edit": .init(zh: "编辑句段 %@", en: "Edit segment %@"),
        "hist.confirm": .init(zh: "确认句段 %@", en: "Confirm segment %@"),
        "hist.lock": .init(zh: "锁定句段 %@", en: "Lock segment %@"),
        "hist.unlock": .init(zh: "解锁句段 %@", en: "Unlock segment %@"),
        "hist.accept": .init(zh: "接受句段修订 %@", en: "Accept revisions %@"),
        "hist.reject": .init(zh: "拒绝句段修订 %@", en: "Reject revisions %@"),
        "hist.acceptAll": .init(zh: "接受全部修订 (%d)", en: "Accept all revisions (%d)"),
        "hist.rejectAll": .init(zh: "拒绝全部修订 (%d)", en: "Reject all revisions (%d)"),
        "hist.replace": .init(zh: "替换句段 %@ (%d)", en: "Replace segment %@ (%d)"),
        "hist.replaceAll": .init(zh: "全部替换 (%d 处 / %d 句)", en: "Replace all (%d / %d segs)"),
        "hist.format": .init(zh: "%@ · 句段 %@", en: "%@ · segment %@"),
    ]
}
