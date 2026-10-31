# Lingua Studio

Native macOS editor for Trados **SDLXLIFF** bilingual files (XLIFF 1.2 + SDL namespaces).

中文说明见下方。

## Download / 下载

**English.** Install the prebuilt app from [GitHub Releases](https://github.com/tomdegnan/LinguaStudio/releases) (macOS 13 Ventura or later, Apple Silicon):

- [LinguaStudio-1.0.dmg](https://github.com/tomdegnan/LinguaStudio/releases/download/v1.0.0/LinguaStudio-1.0.dmg)
- [LinguaStudio-1.0.dmg.sha256](https://github.com/tomdegnan/LinguaStudio/releases/download/v1.0.0/LinguaStudio-1.0.dmg.sha256)

Open the disk image and drag **Lingua Studio** into **Applications**. On first launch, if Gatekeeper prompts, right-click the app and choose **Open**. This repository is source code; the DMG is not stored in git.

**中文。** 预编译安装包在 [GitHub Releases](https://github.com/tomdegnan/LinguaStudio/releases)（macOS 13 Ventura 及以上，Apple Silicon）：

- [LinguaStudio-1.0.dmg](https://github.com/tomdegnan/LinguaStudio/releases/download/v1.0.0/LinguaStudio-1.0.dmg)
- [LinguaStudio-1.0.dmg.sha256](https://github.com/tomdegnan/LinguaStudio/releases/download/v1.0.0/LinguaStudio-1.0.dmg.sha256)

打开磁盘映像，将 **Lingua Studio** 拖入「应用程序」。若首次启动出现 Gatekeeper 提示，可右键应用并选择「打开」。本仓库是源代码，DMG 不放入 git。

---

## English

### What it does

- Open UTF-8 `.sdlxliff` files
- Edit unlocked, translatable segment targets with **protected inline tags**
- Optional SDL track-changes (`x-sdl-added` / `x-sdl-deleted` + `sdl:rev-defs`)
- **Review / verification mode** (Studio-like accept/reject navigation)
- Confirm + next, lock/unlock (when `seg-defs` exist), search/filter, **find next/prev**, **tag-safe replace**
- Session undo/redo
- **Save** to the opened path (atomic) and **Save As…**
- Surgical DOM edits — does not rebuild the whole document from scratch

### Priority: Windows Trados round-trip safety

Lingua Studio mutates the existing `XMLDocument` in place and preserves inter-tag whitespace that Foundation would otherwise drop. **You should still verify** any saved file by opening it in Windows Trados Studio before production use.

### Review mode (核对)

Toggle **核对模式 / Review** in the toolbar (or **⌘⇧E**).

When Review is on:

- Free target editing is restricted (prompt to leave Review first) — same idea as Studio verification focus
- Track-changes recording is disabled while reviewing
- Navigate **only among segments with pending SDL revisions** (`x-sdl-added` / `x-sdl-deleted`) via Next/Previous
- Entering Review auto-filters status to **有修订** when pending exist
- Pending rows are tinted and show an orange **修订** badge; deleted text = red strike, added = green underline
- Accept / Reject current segment; after accept/reject, advances to the next pending
- **Accept All / Reject All** on the current filtered pending set (confirmation alert)

| Action | Shortcut |
|--------|----------|
| Toggle Review mode | ⌘⇧E |
| Next pending revision | ⌘↓ or **F9** |
| Previous pending revision | ⌘↑ or **⇧F9** |
| Accept current segment revisions | ⌘⇧A |
| Reject current segment revisions | ⌘⇧R |

Menu: **核对**.

### Search & replace

Filter bar: source query, target query (**Find what** for replace), replace-with field.

| Option / action | Notes |
|-----------------|--------|
| Aa | Case sensitive |
| 词 | Whole word |
| 正则 | Regular expression |
| Find Next | ⌘G — jump to next row in filtered results |
| Find Previous | ⌘⇧G |
| Replace | Current segment target only; **plain-text gaps only** (never tag tokens) |
| Replace All… | All filtered targets; skips locked / pending-revision / **cross-tag** matches and reports counts |
| Match index | Shows `current / filtered` in the search bar |

If a match would span a protected inline tag, that segment is **skipped** (not partially rewritten).

### Editing (Studio-like, inline)

- Click a row to select it; editable segments open **in place** in the target cell (protected tags, `RichSegmentEditor`).
- Moving to another segment **auto-applies** the current draft (same path as Save / Confirm).
- **⌘↩** — confirm current segment and move to the **next segment in the current filter**, already open for editing (like Studio Ctrl+Enter).
- **Esc** — cancel the current edit (discard draft).
- **⌥↑ / ⌥↓** — previous / next segment in the filtered list (wraps). Plain ↑/↓ stay with the text caret while typing.
- Review mode: targets stay read-only; accept/reject via the review bar.

### Formatting display (bold / italic / …)

SDLXLIFF keeps formatting out of the text: `<g id="pt1">` references `file/header/tag-defs/tag[@id]`, whose `<fmt id="N"/>` points to `fmt-defs/fmt-def[@id=N]/value[@key]`. `LinguaCore/FormattingResolver.swift` reads those once per document (read-only) and the UI renders the result in the table **and** in the inline editor.

- Supported keys: `Bold`, `Italic`, `Underline` (True or a style name such as Single/Double), `Strikethrough`, `TextPosition` (Superscript / Subscript / Normal), `TextColor`, `BackgroundColor` (also Highlight), `FontName`, `FontSize` (parsed, not applied to keep rows compact).
- Colours: `0xRRGGBB`, `#RRGGBB`, `AARRGGBB`, `R,G,B`, `A,R,G,B`, `rgb()`, and common .NET / Word names (Red, DarkBlue, Yellow…). Near-black / near-white text colours are ignored so text stays readable in Dark/Light mode.
- No `fmt` reference? Falls back to the escaped original tag in `bpt` (e.g. `<cf bold=True italic=True>`, `<b>`, `<sup>`, `style="font-weight:bold"`) or the `bpt name`.
- Nested tags combine outer → inner; an inner explicit value wins (e.g. `Bold=False` inside a bold run). `<bx>`…`<ex>` inside one segment are honoured.
- Revision styling (green underline / red strike) is drawn on top of formatting.
- **显示标签 off**: text still looks formatted, without tag chips. On: chips + formatting.
- Display only: formatting is never written back; edits produce exactly the same XML as before.

### Build on Mac Mini (Xcode / CLT)

```bash
cd /path/to/LinguaStudio
chmod +x build.sh
./build.sh
open LinguaStudio.app
```

Requires macOS 13+ and Swift toolchain:

```bash
xcode-select --install   # if needed
swiftc --version
```

Apple Silicon is the default `build.sh` target. On Intel Macs:

```bash
TARGET_ARCH=x86_64 ./build.sh
```

#### Swift Package Manager (optional)

```bash
swift build -c release
swift test                 # LinguaCore XML round-trip + review/replace tests
.build/release/LinguaStudio
```

`LinguaCore` is Foundation-only. The AppKit/SwiftUI UI target is **Mac-only**.

### Layout

```
LinguaStudio/
  Package.swift
  build.sh
  README.md
  Fixtures/sample.sdlxliff
  Sources/LinguaCore/          # XML IO, TagPlan, revisions, search/replace, history
  Sources/LinguaStudio/        # App entry, Store, UI, RichSegmentEditor
  Tests/LinguaCoreTests/       # XCTest round-trip + review/replace (Mac)
  scripts/linux_roundtrip_check.py
  scripts/linux_review_accept_check.py
  scripts/linux_formatting_check.py
  Fixtures/formatting.sdlxliff # fmt-defs sample (bold/italic/underline/sup/sub/colour)
  LinguaStudio.app/Contents/   # Info.plist + MacOS binary after build
```

### Known limitations (not implemented)

- Full Trados QA / TM / termbase features
- Replace never rewrites tag tokens; cross-tag hits are skipped (by design)
- Non–UTF-8 encodings
- Multi-file projects / packages (`.sdlproj`, etc.)
- Comment threads, custom XML attributes beyond common SDL segment fields
- Opening saved files in **Windows Trados Studio has not been verified in this environment**

### Session notes

- Undo/redo is session-only (up to 100 steps), keyed by stable `trans-unit id` + `mid`
- Existing revision markers must be accepted/rejected before editing that text (or use Review mode)
- Invisible-character display does not change document text

---

## 中文

### 这是什么

Lingua Studio 是一个 macOS 原生应用，用于编辑 Trados **SDLXLIFF** 双语文件。目标是在不破坏 Trados 所需结构的前提下，安全地改译文。

### 在 Mac Mini 上编译运行

```bash
cd /path/to/LinguaStudio
chmod +x build.sh
./build.sh
open LinguaStudio.app
```

需要 macOS 13+ 与 Xcode 命令行工具（`swiftc`）。Apple Silicon 默认即可；Intel 请设置 `TARGET_ARCH=x86_64`。

### 核对模式（接近 Studio 基础审阅）

工具栏打开 **核对模式**（或 **⌘⇧E**）：

- 不直接自由编辑译文（会提示先退出核对）——类似 Studio 核对侧重接受/拒绝
- 在含待审修订（`x-sdl-added` / `x-sdl-deleted`）的句段间跳转
- 本句接受 / 拒绝；接受或拒绝后自动跳到下一处待审
- **全部接受 / 全部拒绝**（有确认框），作用于当前筛选范围内的待审句段
- 列表中待审句段橙色标记 +「修订」徽章；删除=红删除线，新增=绿下划线

| 操作 | 快捷键 |
|------|--------|
| 开关核对模式 | ⌘⇧E |
| 下一处待审 | ⌘↓ 或 **F9** |
| 上一处待审 | ⌘↑ 或 **⇧F9** |
| 接受本句修订 | ⌘⇧A |
| 拒绝本句修订 | ⌘⇧R |

菜单：**核对**。

### 搜索与替换

- 原文 / 译文筛选；译文框同时作为「查找内容」
- **下一个 / 上一个**（⌘G / ⌘⇧G）在筛选结果中跳转并选中
- 显示当前匹配序号与筛选段数
- 区分大小写（Aa）、全词（词）、正则
- **替换**：仅当前句译文的纯文本空隙（不动标签 token）
- **全部替换…**：当前筛选结果；跨标签的匹配会整句跳过并统计

### 编辑方式（与 Studio 一致：行内编辑）

- 点击句段即选中，可编辑句段直接在该行译文格内编辑（标签受保护）
- 切换到其他句段时自动提交当前草稿
- **⌘↩** 确认本句并跳到当前筛选中的下一句，且直接进入编辑（类似 Studio 的 Ctrl+Enter）
- **Esc** 取消本次编辑；**⌥↑ / ⌥↓** 在筛选结果中上/下一句（循环），编辑时普通方向键仍用于移动光标
- 核对模式下译文只读，用核对栏接受/拒绝

### 富文本格式显示

- 读取文件头 `tag-defs` + `fmt-defs`（只读），在列表和行内编辑器里显示 **粗体 / 斜体 / 下划线 / 删除线 / 上标 / 下标 / 文字颜色 / 背景(高亮)色 / 字体名**；字号只解析不应用（保持行高整齐）
- 没有 `fmt` 引用时，回退解析 `bpt` 中原始标签（如 `<cf bold=True>`、`<b>`、`<sup>`）
- 嵌套标签由外向内叠加，内层显式值优先（如粗体里的 `Bold=False`）
- 关闭「显示标签」时仍显示格式、不显示标签；打开时标签 + 格式
- 修订样式（绿色下划线 / 红色删除线）叠加在格式之上
- 仅用于显示，不会写回文件；编辑生成的 XML 与之前完全相同
- 中文字体没有斜体字形：编辑器中对中文斜体做倾斜处理；只读列表中中文斜体可能显示为正体

### 已实现

1. 打开 UTF-8 `.sdlxliff`，按 `trans-unit` → `seg-source`/`target` 的 `mrk[@mtype='seg']` + `mid` 解析
2. 尊重 `translate="no"` 与 `seg-defs/seg@locked`
3. 原文/译文显示，可切换行内标签；编辑时标签受保护（TagPlan + attachment token）
4. 对未锁定可译句段做外科手术式 DOM 修改
5. 可选修订跟踪：`x-sdl-added`/`x-sdl-deleted` + `sdl:rev-defs`；核对模式接受/拒绝
6. 保存到原路径（原子写入）+ 另存为；尽量保留标签间空白
7. 确认并下一句、锁定/解锁、搜索筛选、标签安全替换、脏标记、会话撤销/重做

### 已知限制

- 未实现 Trados 全套 QA / 记忆库 / 术语库等功能
- 替换不会改标签；跨标签匹配会跳过（有意为之）
- **请在 Windows 版 Trados Studio 中打开保存后的文件做往返验证**

### Linux 说明

本仓库可在 Linux 上编写与存放；AppKit UI 无法在 Linux 链接。可用：

```bash
python3 scripts/linux_roundtrip_check.py
python3 scripts/linux_review_accept_check.py
python3 scripts/linux_formatting_check.py
```

对样例夹具做结构级往返与「检测待审 → 接受 → 该 mid 无待审」检查。完整 Swift/`swift test` 请在 Mac 上运行。
