# Snipaste 官方文档逐项对照（NetworkMonitor 现状差距清单）

> 用途：把 Snipaste 官方 wiki 里的**每一个快捷键与每一个功能项**逐条对到本项目（toolbar / NetworkMonitor，Swift 6.3 + AppKit 菜单栏 App）的现状，产出可勾选的差距清单与优先级。
> 本文件是**新写的一份**核对报告，与旧的 `docs/调研/Snipaste-功能调研与实现评估.md` 无继承关系：旧文档只作背景读过，其中任何数字（含 105.5 人日那套口径）**均未采用**。

## 0. 调研口径与取证方法

### 0.1 数据来源（只用官方文档，无一条来自记忆）

抓取命令（八份，全部 `--compressed`，全部 HTTP 200，合计 123 367 字节）：

```bash
curl -sL --compressed "https://docs.snipaste.com/wiki/内置快捷键.md"    # 2283
curl -sL --compressed "https://docs.snipaste.com/wiki/基础操作.md"      # 6643
curl -sL --compressed "https://docs.snipaste.com/wiki/高级技巧.md"      # 1239
curl -sL --compressed "https://docs.snipaste.com/wiki/高级设置.md"      # 6590
curl -sL --compressed "https://docs.snipaste.com/wiki/命令行选项.md"    # 10118
curl -sL --compressed "https://docs.snipaste.com/wiki/专业版.md"        # 13194
curl -sL --compressed "https://docs.snipaste.com/wiki/常见问题.md"      # 4371
curl -sL --compressed "https://docs.snipaste.com/wiki/更新日志.md"      # 78929
```

「官方版本归属」列的判据：
1. 主判据 = `专业版.md` 的「Snipaste 2 专业版/免费版 对比」表（逐项 ✔️/❌）；
2. 版本号判据 = `更新日志.md` 条目（下文标成 `vX.Y` 的均指该条目首次出现的大版本）；该文档开头声明「在线版可能超前于你所使用的软件版本」，因此版本号只作「归属哪一档」的旁证，不作「你手上这个版本有没有」的断言；
3. 平台限定项（仅 Windows / 仅 Linux / 仅微软商店版）单独标注。

### 0.2 Mac 口径说明（重要）

`内置快捷键.md` 首行原文：「以下按键适用于 Windows/Linux 操作系统，对于 Mac 操作系统，需将 Ctrl 替换成 Cmd.」

因此本报告一律按 **Mac 口径**书写键位（官方 Ctrl → ⌘）。同样受影响的还有：
- `命令行选项.md` 的调用示例给的是 `/Applications/Snipaste.app/Contents/MacOS/Snipaste snip --full -o clipboard` —— 命令行能力在 Mac 版存在；
- `常见问题.md` 有一条「Mac 版 / Linux 版 / 滚动截图 / GIF 录制 …… 请关注 [这里]」，说明 Mac 版功能并非全量。**凡涉及「Mac 版实际是否提供」的条目，本报告写「未验证」而不是猜测**；本报告只对照文档描述的行为。

### 0.3 现状核查方法（每个「缺失」都附「我查了什么、返回什么」）

两级取证，优先级按要求：

1. **知识图谱优先（符号级定位）**：
   ```bash
   ~/.local/bin/codebase-memory-mcp cli search_graph \
     --project Users-bsfeng-IdeaProjects-toolbar-NetworkMonitor --query SnipOverlayView
   # → total: 67 / search_mode: bm25 / results: 50（含 file + lines 区间）
   ```
   图谱只会返回**已存在的符号**，所以它用于「已实现项的文件:行号」定位（下文多数已实现行的行号来自图谱与随后 read 的双重确认）。

2. **grep 兜底（功能有无）**：图谱搜不到不存在的功能，因此**所有「缺失」结论一律由 grep 给出**，每行证据写成「grep 模式 → 命中数 → 命中内容是否相关」。为了可复跑，附录 A 列出本轮实际跑过的全部 grep 命令。

3. 读码确认：凡断言「部分实现」，都读到了对应文件的具体实现（行号在下文给出）。

### 0.4 记号

- 现状取值只有五种：**已实现** / **部分实现** / **缺失** / **有但语义不同** / **超出官方**（比官方多做，通常是因为本项目是菜单栏 App）。
- 「证据」列的 `路径:行` 均为仓库相对路径，行号以本轮读到的文件为准。

---

## 1. 截图域（Snip）

### 1.1 截图内快捷键（官方「只对截图有效」表 + 通用表中的选区相关键）

| 编号 | 官方行为（原文摘要） | 本项目现状 | 证据 | 官方版本归属 |
|---|---|---|---|---|
| SNIP-K01 | 「Tab 切换检测窗口/检测界面元素」 | **部分实现**：`Tab` → `.toggleWindowDetection`，只在「窗口检测 开/关」之间切；**没有「界面元素」这一被切换的另一半**（见 SNIP-F14） | `NetworkMonitorUI/SnipKeyCommand.swift:101`（`case KeyCode.tab: return .toggleWindowDetection`）；`Snip/SnipOverlayView.swift:306-309`（`windowDetectionEnabled.toggle()`）；界面元素检测本身 grep 0 命中（SNIP-F14） | 免费 |
| SNIP-K02 | 「` 或 ! 显示/隐藏捕获的鼠标指针」 | **部分实现**：``` 反引号有效；`!` 未绑定 | `SnipKeyCommand.swift:97`（`case KeyCode.backtick: return .toggleCursor`）；字母分支 `SnipKeyCommand.swift:110-118` 无 `"!"`；`SnipController.swift:183-203` 为重捕获实现 | 免费 |
| SNIP-K03 | 「Ctrl + A 设置截屏区域为全屏」 | **已实现**（Mac 为 ⌘A） | `SnipKeyCommand.swift:129`（`case "a": return .selectAll`）；`SnipOverlayView.swift:314-317`（`state.select(bounds)`） | 免费 |
| SNIP-K04 | 「R 将截屏区域设置为上一次成功截图时的区域」 | **已实现** | `SnipKeyCommand.swift:116`（`case "r": return .restoreLastSelection`）；`SnipOverlayView+Actions.swift:129-133`；持久化 `SnipController.swift:31,89-99` | 免费 |
| SNIP-K05 | 「, 切换到上一次截屏记录」 | **已实现**（循环到更早一条） | `SnipKeyCommand.swift:99`；`SnipOverlayView+Actions.swift:107-117`（`index += forward ? 1 : -1`） | 免费 |
| SNIP-K06 | 「. 切换到下一次截屏记录」 | **已实现** | `SnipKeyCommand.swift:100`；同上 `stepHistory(forward: true)` | 免费 |
| SNIP-K07 | 「F5 刷新截图」 | **缺失** | grep `F5|refreshSnip|刷新截图` 于 `NetworkMonitor/Sources` → 7 命中，全部无关（`Clipboard/GlobalHotKey.swift:85` 只是键名显示表里的 `"F5"`；其余为色值 0xF5xxxx）。截图键盘表 `SnipKeyCommand.swift` 无 F5 键码（`kVK_F5` = 96 未出现） | **专业版**（"刷新截图" v2.7.2，"F5 快捷键" v2.8.2） |
| SNIP-K08 | 「Ctrl + ↑←↓→ 将截屏区域相应边界扩大 1 像素」 | **已实现**（语义为「四边同时外扩 1」，非「只扩对应那条边」） | `SnipKeyCommand.swift:102-105`（方向键 → `.nudge`）；`SnipOverlayView+Actions.swift:135-145`（`modifiers.contains(.control) → state.expand(by:)` → `SnipSelectionState.swift:109-112` `insetBy(dx:-delta,dy:-delta)` **四边都动**） | 免费 |
| SNIP-K09 | 「Shift + ↑←↓→ 将截屏区域相应边界缩小 1 像素」 | **已实现**（同上，四边同时内缩） | `SnipOverlayView+Actions.swift:139-140` → `SnipSelectionState.swift:115-120` | 免费 |
| SNIP-K10 | 「Ctrl + T 直接将截图贴到屏幕」 | **已实现**（⌘T），另有鼠标中键等价入口 | `SnipKeyCommand.swift:130`（`case "t": return .pin`）；`SnipOverlayView.swift:163-168`（`otherMouseDown` → `requestPin()`，注释明确写「Snipaste 的 Ctrl+T 等价操作」） | 免费 |
| SNIP-K11 | 「Enter 复制截图并退出截屏」 | **已实现** | `SnipKeyCommand.swift:96`（return/小键盘回车 → `.confirm`）；`SnipOverlayView.swift:292-294` → `SnipController.swift:205-219` | 免费 |
| SNIP-K12 | 「Esc 中止截屏」 | **已实现**（且 Esc 优先结束整次截图，不再先清草稿——见 `SnipOverlayView.swift:285-291` 的注释与实现） | `SnipKeyCommand.swift:95`；`SnipOverlayView.swift:257-259` 另覆写 `cancelOperation` 兜住 AppKit 的取消链路 | 免费 |
| SNIP-K13 | 「鼠标右键单击 重新设置截屏区域/中止截屏」 | **有但语义不同**：本项目右键**一律中止整次截图**，没有「重新设置区域」这一分支；且编辑标注时右键不能「结束当前图案」（见 ANN-K05） | `SnipOverlayView.swift:170-176`（`if event.type == .rightMouseDown { delegate?.overlayViewDidCancel(self); return }`）与 `:232-234`（`rightMouseDown` 同样 cancel） | 免费 |
| SNIP-K14 | 通用：「Alt 显示放大镜」 | **有但语义不同**：放大镜**常驻显示**（选区内阶段反而隐藏），没有「按 Alt 才召唤」的开关 | 常驻判定 `SnipOverlayView+Actions.swift:182-184`（`if state.phase != .selected { drawMagnifier(...) }`）；绘制 `SnipOverlayView+Drawing.swift:80-137`；`SnipKeyCommand.swift` 全表无 option 分支（Alt 不产生命令） | 免费（专业版可自定义样式/完全关闭） |
| SNIP-K15 | 通用：「Shift 放大镜可见时，切换颜色格式」 | **有但语义不同**：本项目`Shift`（任一按下）就切 hex↔RGB，不依赖放大镜可见；且与「Shift 缩小选区」共用同一修饰键 | `SnipOverlayView.swift:340-345`（`flagsChanged` 直接 `colorFormat = colorFormat == .hex ? .rgb : .hex`） | 免费 |
| SNIP-K16 | 通用：「C 放大镜可见时，复制颜色值」 | **已实现**（不要求放大镜可见） | `SnipKeyCommand.swift:115`（`case "c": return .copyColor`）；`SnipOverlayView+Actions.swift:95-104`（写 `colorFormat.text(for:)` 到剪贴板） | 免费 |
| SNIP-K17 | 通用：「W S A D 将鼠标指针移动 1 像素」 | **有但语义不同**：本项目 WASD 移动的是**选区**（nudge），不是鼠标指针 | `SnipKeyCommand.swift:111-114`（`a/d/w/s` → `.nudge`）→ `SnipOverlayView+Actions.swift:141-143` `state.move(by:)` | 免费（专业版可自定义 WASD/方向键互换） |
| SNIP-K18 | 通用：「↑←↓→ 非编辑状态下，将截屏区域/贴图窗口移动 1 像素」 | **已实现**（截图内=移动选区；贴图窗=未实现，见 PASTE-K20） | 截图：`SnipKeyCommand.swift:102-105` + `SnipOverlayView+Actions.swift:142`；贴图窗 `Pin/PinWindow.swift:56-81` 的 `keyDown` 无方向键分支 | 免费 |
| SNIP-K19 | 通用：「空格键 显示/隐藏标注工具条」 | **已实现** | `SnipKeyCommand.swift:98`（`case KeyCode.space: return .toggleToolBar`）；`SnipOverlayView.swift:297-301`（同时收起二级面板） | 免费 |

### 1.2 截图功能项（含专业版独占）

| 编号 | 官方行为（原文摘要） | 本项目现状 | 证据 | 官方版本归属 |
|---|---|---|---|---|
| SNIP-F01 | 「开始截图：快捷键（默认为 F1）；鼠标左键单击托盘图标」 | **有但语义不同**：热键默认 `⌃⇧S`（不是 F1——代码注释说明无修饰单键在 macOS 27 会与系统媒体键抢通道、实测连按 3 次只到 1 次）；托盘**左键单击打开面板**，右键才是菜单，「点托盘即截图」没有 | `Snip/SnipHotKeyPreferences.swift:34-35`（`kVK_ANSI_S` + `controlKey|shiftKey`）；`MenuBarManager.swift:117-135`（`handleStatusButton`：左键 `togglePanel`、右键 `showStatusItemMenu`） | 免费 |
| SNIP-F02 | 「自由矩形区域截屏」 | **已实现**（拖拽新建、8 向手柄、移动、单击选窗判定） | `SnipSelectionState.swift:49-72,132-154`；`SnipOverlayView.swift:170-230` | 免费 |
| SNIP-F03 | 「一次成功的截图 = 保存到剪贴板 / 保存到文件 / 保存到贴图 / 快捷保存」 | **已实现四种**（⌘C、⌘S、⌘T、⌘⇧S），另有「复制后自动保存」开关 | `SnipKeyCommand.swift:126-133`；`SnipController+Export.swift:10-23,49-61,62-74` | 免费 |
| SNIP-F04 | 「取消当前截图：Esc / 工具条关闭按钮 / 非编辑状态右键 / 有其他程序窗口被激活（可在选项关闭此行为）」 | **部分实现**：Esc 与右键有、工具条有「取消」按钮；**「别的程序被激活就取消截图」未实现** | Esc：`SnipOverlayView.swift:257-259`；工具条取消 `Snip/SnipToolBarView.swift:8-20` + `SnipOverlayView+Annotation.swift:98-105`；失焦取消：grep `didResignActive|willResignActive|applicationDidResignActive` → **0 命中** | 免费 |
| SNIP-F05 | 「回放截图记录：, 或 .；只有成功的截图才进记录；记录最大数量可在选项窗口设置」 | **部分实现**：, / . 有、只记成功截图有；**记录的是「选区矩形」不是图像**，容量硬编码 10、无设置项 | `SnipSelectionHistoryCoding.swift:9`（`defaultCapacity = 10`）；`SnipController.swift:93-105`（`remember` 存 rect）；设置页 `SettingsCapturePane.swift:54-61` 无该项 | 免费 |
| SNIP-F06 | 「逐像素控制光标移动：W A S D」 | **有但语义不同**（WASD 移动选区，不移动光标，见 SNIP-K17） | 同 SNIP-K17 | 免费 |
| SNIP-F07 | 「像素级控制截取区域：按住左键 + WASD 可实现移动/扩大/缩小」 | **缺失**（按住左键期间 WASD 不参与调整） | grep 无按住态 WASD 分支；`SnipOverlayView.swift:209-219`（`mouseDragged` 只走 `state.drag/adjust`，不读键盘修饰或字母） | 免费 |
| SNIP-F08 | 「放大镜会在合理的时机自动出现和隐藏，需要时按 Alt 召唤」 | **有但语义不同**（常驻 + 无 Alt 召唤，见 SNIP-K14） | 同 SNIP-K14 | 免费 |
| SNIP-F09 | 「取色：放大镜可见时按 C 复制该像素颜色值（RGB/Hex）；之后可以 F3 贴出，或 Ctrl+V 贴到其他程序里；Shift 切颜色格式」 | **部分实现**：C 取色有、两种格式有、Shift 切换有；**「F3 贴出（色卡）」与「⌘V 贴到其他程序」两条联动缺失** | 取色 `SnipOverlayView+Actions.swift:95-104`；格式 `SnipPixelSampler.swift:28-39`；F3 贴出：贴图热键是 `⌃⇧V`（`SnipHotKeyPreferences.swift:36-37`）且不做「把剪贴板颜色主动塞进别的 App」——grep 全仓无向外部 App 发送 ⌘V 的实现（`SnipController+Pin.swift` 只贴到本 App 窗口） | 免费 |
| SNIP-F10 | 「延时截屏」（专业版对比表：延时截屏 ✔️ 免费；命令行 `--delay TIME`） | **部分实现**：只有固定 3 秒的独立热键 `⌥⇧D`，**无倒计时提示、无可选时长、无 CLI** | `SnipController.swift:66-72`（`delayedSnipDelay = 3_000_000_000`）；`SnipController.swift:118-126`（`Task.sleep` 后 `beginSnip()`，期间无 UI） | 免费 |
| SNIP-F11 | 「自定义尺寸截屏：免费版在开始截图前弹对话框指定尺寸；专业版还可进入截图后点尺寸图标指定」 | **已实现专业版语义**（进入截图后点尺寸标签输入 `800x600`）；免费版的「截图前对话框」缺失 | `SnipOverlayView.swift:184-187`（点 `sizeLabelFrame` → `beginSizeEditing`）；`SnipOverlayView+Actions.swift:52-93`；解析 `SnipSizeInput.swift:7-23`（支持 x/*/,/空格） | 免费 / 专业版 |
| SNIP-F12 | 「固定截图区域长宽比」（专业版对比表）+ 命令行 `--keep_aspect_ratio` | **部分实现**：按住 Shift 拖动手柄时锁定当前比例；**没有「把比例锁死」的开关，也没有 CLI 参数** | `SnipOverlayView.swift:216`（`state.adjust(to:lockingAspect: event.modifierFlags.contains(.shift))`）；`SnipSizeInput.swift:29-72`（`SnipAspectLock.lockedResize`）；CLI grep `--keep_aspect_ratio` → 0 | **专业版**（v2.2.3 固定长宽比；v2.8.6 `--keep_aspect_ratio`） |
| SNIP-F13 | 「窗口检测」（免费版即提供，悬停高亮 + 单击选整窗） | **已实现且超出**：白名单层级 0/20/24/25（普通窗口 / 程序坞 / 菜单栏 / 状态栏项）、Dock 整屏容器按贴边带裁边、自家 popover 不排除 | `ScreenCaptureService.swift:72-97`；`SnipWindowInfo.swift:9-36`（层级白名单）、`:82-107`（命中与门槛）、`:126-161`（Dock 贴边带与 `selectionFrame`）；标签 `NetworkMonitorUI/SnipWindowLabel.swift:11-49` | 免费（粒度超出：官方免费版只做窗口，元素级才要专业版） |
| SNIP-F14 | 「界面元素检测」（专业版对比表：界面元素检测 ❌ 免费 / ✔️ 专业版）+ 「检测界面父/子元素 ❌ / ✔️（Linux 版不支持）」 | **缺失**（只到 CGWindowList 的窗口粒度，没有 AX 元素粒度，也没有滚轮切父/子） | grep `AXUIElement|AXUIElementCopy` → **0 命中**；grep `parent|子元素|elementDetect` 于 Sources → 3 命中，分别属 Token 分页与菜单 Tab（`HarnessTokenModels.swift:164-165`、`MenuTabBarView.swift:90`），**与截图无关**；`ScreenCaptureService.swift:61-71` 注释自述「逐个图标要 Accessibility API，不在本轮范围」 | 免费（元素检测）/ **专业版**（父·子元素切换，v1.10 起） |
| SNIP-F15 | 「超级截屏：无需占用全局快捷键，按 Win/Cmd + 鼠标拖拽即完成截图」 | **缺失** | grep `superSnip|超级截屏` → 命中 200+ 但全部是 Swift 的 `super.` 调用（如 `super.keyDown`）；无「修饰键按下即进入截图」的实现（`main.swift` 只有 NSApplication 启动） | **专业版**（Mac 版曾修「超级截图相关问题」v2.10.x） |
| SNIP-F16 | 「圆角矩形截图」 | **缺失** | grep `roundedSnip|圆角截图` → 0；`圆角|cornerRadius` 225 命中全部是 UI 圆角样式（如 `SnipToolBarView.swift:157`） | **专业版**（v2.8.6） |
| SNIP-F17 | 「活动窗口截屏」（对比表 ❌/✔️）+ 命令行 `snip --active-window` | **缺失**（窗口检测能点选当前窗口，但没有「一键截活动窗口」的命令或键） | grep `--active-window|activeWindow` → 0；`SnipKeyCommand.swift` 无对应命令 | **专业版** |
| SNIP-F18 | 「输入截屏区域尺寸」（对比表 ❌/✔️ 专业版） | **已实现**（同 SNIP-F11 的尺寸输入框） | 同 SNIP-F11 | **专业版**（对比表口径） |
| SNIP-F19 | 「切换截屏尺寸单位 (px/dip)」 | **缺失** | grep `dip|单位.*截屏|sizeUnit` → 无截屏相关命中；尺寸标签固定输出点数（`SnipOverlayView+Drawing.swift:41-59`） | **专业版**（v2.5） |
| SNIP-F20 | 「白板模式」（对比表 ✔️ 免费） | **已实现**（`⌥⇧W`，纯白画布 + 整屏选区 + 标注后可复制） | `SnipController+HotKeys.swift:171-239`（`registerWhiteboardHotKey` / `beginWhiteboard` / `makeWhiteboardImage`）；`SnipOverlayView+Actions.swift:242-250`（`selectFullBoard`） | 免费 |
| SNIP-F21 | 「透明白板模式」（屏幕内容不会冻住） | **缺失** | grep `透明.*白板|transparentWhiteboard` → **0 命中**；`beginWhiteboard` 只画纯白底（`SnipController+HotKeys.swift:236-237`） | **专业版**（v2.2.2 改善白板；v2.3.1 可开关穿透） |
| SNIP-F22 | 「捕捉光标图案」（对比表 ✔️ 免费） | **已实现**（反引号切换后重捕获含光标） | `SnipController.swift:183-203`（`overlayViewDidToggleCursor` → `captureAllDisplays(includeCursor:)`）；`ScreenCaptureService.swift:113-118,160-177`（`showsCursor`） | 免费（Mac 版 v2.6 才支持捕捉光标图案） |
| SNIP-F23 | 「精确控制光标移动 / 重放截图历史 / 自动保存 / 快速保存」 | **部分实现**：重放历史、自动保存、快速保存有；「光标逐像素移动」缺（同 SNIP-F06） | 自动保存 `SnipController.swift:210-217`；快速保存 `SnipController+Export.swift:49-61`；历史见 SNIP-F05 | 免费 |
| SNIP-F24 | 「带阴影/边框保存」（对比表 ❌/✔️ 专业版）+ 命令行 `--shadow` / `--no-shadow` | **缺失** | grep `shadow|阴影` → 4 命中：`ClipboardCardView.swift:9,80`、`Transfer/ScanPageRenderer.swift:26`、`ScreenCaptureService.swift:159`（注释里写「可控制光标与阴影」，实际 `configuration` 只设 `showsCursor`/`dynamicRange`，**没有阴影输出**） | **专业版**（v2.2 带阴影复制/保存；v2.5 可指定阴影颜色宽度） |
| SNIP-F25 | 「复制截图为文件」（对比表 ❌/✔️ 专业版） | **缺失**：复制只写 `NSImage`，剪贴板里没有文件 URL，无法在 Finder 里 ⌘V 落成文件 | `SnipController+Export.swift:18-22`（`pasteboard.writeObjects([image])`，无 `writeObjects([url])`/file promise） | **专业版** |
| SNIP-F26 | 「原生分享（Windows 10+）」 | **缺失**（平台限定，可视为不适用） | grep `NSSharingService|sharingService` → 0 | **专业版**（Windows 限定） |
| SNIP-F27 | 「配合 Listary 使用（手动保存文件时隐藏截图窗口）」 | **缺失**（Windows 生态绑定，可视为不适用） | grep `Listary` → 0 | **专业版**（Windows 限定） |
| SNIP-F28 | 「发送截图到其他应用程序（通过自定义命令行参数）」+ `-o exec(COMMAND)` | **缺失**（无 CLI，也无 exec 钩子） | 见 SYS-F02 | **专业版**（v2.3 多输出方式；v2.5.2 起支持 `exec()`） |
| SNIP-F29 | 「保存所有的截图记录（连未保存的也进历史，防误触 Esc 丢图）」 | **缺失**（本项目只存选区矩形，且只在成功时记） | `SnipController.swift:93-99`；未保存路径不调用 `remember` | **专业版** |
| SNIP-F30 | 高级设置 `[Snip] anchors_threshold`（选区小于阈值时自动隐藏手柄，默认 80 × DPI） | **缺失**（手柄始终绘制，8 个） | `SnipOverlayView+Drawing.swift:23-39`（`drawHandles` 无阈值判断）；grep `anchors_threshold` → 0 | 免费（高级设置项） |
| SNIP-F31 | 高级设置 `[Snip] animated_region_transition`（检测窗口/元素时用过渡动画） | **缺失**（高亮框是立即切换，无过渡） | `SnipOverlayView.swift:152-161` `updateHoveredWindow` 直接赋值 + `needsDisplay` | 免费（v2.10.2） |
| SNIP-F32 | 高级设置 `[Snip] exclude_from_detection` / `crashes`（窗口检测排除/降级程序名单） | **缺失** | 两者文档均注「此选项为 Windows 独占」；本项目层级白名单里也没有按应用名排除（`SnipWindowInfo.swift:98-107` 只按层级/PID/尺寸） | 平台独占（Windows） |
| SNIP-F33 | 屏幕录制权限缺失时的行为 | **超出官方**（文档无此条）：本项目有专门的引导弹窗 + 跳转系统设置 + 失败轻提示条 | `Snip/SnipPermissionGuide.swift:13-31`；`Snip/SnipFailureNotice.swift:15-18,27-76` | —（本项目自加） |

---
## 2. 标注域（Annotation）

### 2.1 标注快捷键（官方「通用」表 + 「只对截图有效」表中作用于标注的键）

| 编号 | 官方行为（原文摘要） | 本项目现状 | 证据 | 官方版本归属 |
|---|---|---|---|---|
| ANN-K01 | 「鼠标滚轮 或 1 2 或 [ ] 调整画笔粗细（编辑模式时）」 | **缺失** | 截图覆盖层的 `scrollWheel` 只改**文字**字号并强制要求「已选中文字」（`SnipOverlayView.swift:237-249`）；`SnipKeyCommand.swift:110-118` 字母分支无 `1`/`2`，`KeyCode` 表（`:65-78`）无 `[```]`；线宽只能经工具条二级面板换（`SnipToolBarView.swift:79-81`） | 免费（笔尖数量 1–5 为专业版） |
| ANN-K02 | 「Ctrl + Z 撤销上一次标注（可以再恢复）」 | **已实现**（⌘Z） | `SnipKeyCommand.swift:132`；`SnipOverlayView.swift:324-326`（`annotationStack.undo()`）；栈实现 `SnipAnnotationStack.swift` | 免费 |
| ANN-K03 | 「Ctrl + Y 恢复下一个标注」 | **有但语义不同**：恢复是 `⌘⇧Z`，`⌘Y` 未绑定 | `SnipKeyCommand.swift:131`（`case "z" where .shift: return .redo`）；全表无 `"y"` | 免费 |
| ANN-K04 | 「Ctrl + Shift + Z 移除所有标注（无法再恢复）」 | **有但语义不同**（本项目 `⌘⇧Z` = **重做**，与官方「清空全部」相反） | `SnipKeyCommand.swift:131-132`；`SnipOverlayView.swift:327-329`（`redo()`） | 免费 |
| ANN-K05 | 「鼠标右键单击 结束对当前标注的编辑」/ 基础操作「手动结束当前图案：单击鼠标右键」 | **有但语义不同**：右键**直接取消整次截图**，正在画的图形被丢弃 | `SnipOverlayView.swift:170-176`、`:232-234`（两处都 `delegate?.overlayViewDidCancel(self)`） | 免费 |
| ANN-K06 | 「Ctrl + C 复制图像」 | **已实现**（⌘C 等价回车确认） | `SnipKeyCommand.swift:128`；`SnipOverlayView.swift:332-333`（`case .copyImage: confirm()`） | 免费 |
| ANN-K07 | 「Ctrl + S 将图像保存为文件」 | **已实现** | `SnipKeyCommand.swift:127`；`SnipOverlayView.swift:330-331` | 免费 |
| ANN-K08 | 「Ctrl + Shift + S 保存图像到快捷保存目录」 | **已实现** | `SnipKeyCommand.swift:126`；`SnipController+Export.swift:49-61` | 免费 |
| ANN-K09 | 「Ctrl + P 发送图像到打印机」 | **缺失** | grep `NSPrint|printOperation|发送到打印机` → **0 命中** | 免费 |
| ANN-K10 | 基础操作「切换直线/箭头：Tab」 | **有但语义不同**：本项目 Tab 用于「窗口检测开关」，直线与箭头是**两个独立工具**（不互相切换） | `SnipKeyCommand.swift:101`（Tab → `.toggleWindowDetection`）；`SnipTool.swift:7-9`（`line` / `arrow` 两个 case） | 免费 |
| ANN-K11 | 「画直线/折线：选中折线工具后，拖拽左键是画单条直线，多次点按左键是画折线」 | **部分实现**：多次点按画折线有（回车提交），**「同一工具下拖拽即单条直线」没有**（直线要切到 `line` 工具） | `SnipOverlayView+Annotation.swift:167-181`（polyline：每次都追加点）；`:265-273`（`finishPolylineDraft` 只在回车时提交） | 免费 |
| ANN-K12 | 「调整文字大小：拖动文字框四角」 | **有但语义不同**：本项目滚轮改 `fontScale`，**没有文字框四角手柄** | `SnipOverlayView.swift:237-249`；`SnipAnnotation.swift:102-105`（`fontScale`） | 免费 |
| ANN-K13 | 「旋转文字：拖动文字框上方的小圆点」 | **有但语义不同**：本项目 `⌘R` 每次 +90° | `SnipKeyCommand.swift:133`（`case "r": return .rotateSelectedText`）；`SnipOverlayView+Annotation.swift:286-294` | 免费 |
| ANN-K14 | 「将旋转过的文字重新变为水平的：按住 Shift 再拖动文字框四角」 | **缺失** | 文字无拖拽缩放入口（同 ANN-K12）；`Shift` 在标注器里不参与任何标注变换（`SnipOverlayView+Annotation.swift:249-262` 不读修饰键） | 免费 |
| ANN-K15 | 高级技巧「快速标注界面元素：截屏时选中矩形/椭圆/记号笔/马赛克/高斯模糊/橡皮擦的矩形填充画笔，按下鼠标右键即可自动选中界面元素（需启用自动检测界面元素）」 | **缺失**（右键是取消，且无元素检测） | `SnipOverlayView.swift:232-234`；元素检测 grep 见 SNIP-F14（0 命中） | 免费（依赖专业版父·子元素能力） |
| ANN-K16 | 高级技巧「调节画笔透明度：点击工具条中那个大的颜色按钮，更改其 Alpha 通道（0–255）」 | **缺失**：颜色只有 7 档固定色，`SnipAnnotationStyle` 虽有 `alpha` 字段（`SnipAnnotation.swift:10-16`）但**没有任何 UI 能改** | 调色板 `SnipToolBarView.swift:80`（7 色常量）；`SnipToolPanelView.swift:12-18`（`.colors` 只给色值）；无 NSColorPanel 调用（附录 A g18） | 免费（专业版可滚轮调透明度） |
| ANN-K17 | 高级技巧「Shift 标注：矩形→正方形、椭圆→圆形、直线/箭头→水平/垂直/45 度、画笔→中途变直线、马克笔→水平/垂直/45 度、马赛克/模糊/橡皮擦→同画笔」 | **缺失** | `SnipOverlayView+Annotation.swift:249-262`（`handleAnnotationMouseDragged` 直接用 `point`，不读修饰键）；`SnipOverlayView.swift:216` 的 `Shift` 只作用于**选区**手柄锁比例 | 免费 |
| ANN-K18 | 常见问题「标注文字时怎样结束输入：鼠标右键点一下（所有标注都可以这样操作）」 | **有但语义不同**：文字用回车提交（`⌘`无）、右键会取消整次截图 | `SnipOverlayView+Annotation.swift:222-240`（`commitTextEditing`）；`SnipOverlayView.swift:232-234` | 免费 |

### 2.2 标注功能项（含专业版独占）

| 编号 | 官方行为（原文摘要） | 本项目现状 | 证据 | 官方版本归属 |
|---|---|---|---|---|
| ANN-F01 | 「矩形/椭圆」（对比表 ✔️/✔️） | **已实现**（含 `filled` 实心与 `dashed` 虚线字段） | `SnipTool.swift:7-8`；`SnipAnnotationRenderer.swift:29-43` | 免费 |
| ANN-F02 | 「直线/折线/箭头」（✔️/✔️） | **已实现** | `SnipTool.swift`（`line/polyline/arrow`）；`SnipAnnotationRenderer.swift:44-62,103-120` | 免费 |
| ANN-F03 | 「画笔」（✔️/✔️） | **已实现**（`freehand`，轨迹点） | `SnipTool.swift:11`；`SnipAnnotationRenderer.swift:55-61` | 免费 |
| ANN-F04 | 「记号笔」（✔️/✔️，独立透明度，独立笔尖） | **缺失** | `SnipTool.allCases` 只有 10 个 case（`SnipTool.swift:7-16`），无 marker；grep `记号笔|marker|highlighter` → 2 命中且都是剪贴板 `markerType`（`ClipboardPaster.swift:40,96`） | 免费 |
| ANN-F05 | 「马赛克/模糊」（✔️/✔️） | **已实现**（CPU 像素化 + 高斯模糊） | `SnipMosaicProcessor.swift:19-50`；`SnipAnnotationCompositor.swift:29-65` | 免费 |
| ANN-F06 | 「文本标注」（✔️/✔️） | **部分实现**：单行 CoreText 绘制、可改字号、可旋转 90°；**没有背景填充、没有描述描边、没有多行** | `SnipAnnotationRenderer.swift:67-100`（`CTLineCreateWithAttributedString` 单行） | 免费 |
| ANN-F07 | 「橡皮擦」（✔️/✔️） | **已实现**（按点删除 / 轨迹段删除） | `SnipTool.swift:16`；`SnipOverlayView+Annotation.swift:296-325` | 免费 |
| ANN-F08 | 「序号标注」（❌/✔️） | **缺失** | grep `序号|numbering|badgeNumber` → 13 命中，均为剪贴板序号/Token 排行序号等无关注释；`SnipTool` 无此 case | **专业版**（v2.4，v2.5.2 可 +/- 调序号） |
| ANN-F09 | 「放大镜标注（圆内放大局部）」（❌/✔️） | **缺失** | grep `放大镜标注|magnifierAnnotation` → 无；`drawMagnifier` 只是取色放大镜（`SnipOverlayView+Drawing.swift:80-137`），不是标注图元 | **专业版**（v2.6） |
| ANN-F10 | 「圆角矩形标注」（❌/✔️） | **缺失**（矩形只有直角） | `SnipAnnotationRenderer.swift:30-36`（`context.stroke(rect)` / `fill(rect)`，无圆角路径）；`SnipAnnotationKind` 无 roundedRect | **专业版**（v2.4） |
| ANN-F11 | 「虚线/点线（矩形/椭圆/直线/折线/箭头/画笔）」（❌/✔️） | **部分实现（能力在、入口无）** | 模型 `SnipAnnotation.swift:39-49`（`dashed`）；渲染 `SnipAnnotationRenderer.swift:25-27`（`setLineDash`）；但 `SnipToolPanelView`/`SnipToolBarView` 无切换入口，`currentStyle` 初值 `dashed=false` 且无修改点（grep `dashed` 24 命中，Sources 里落在 Snip 的只有 2 处模型/渲染） | **专业版**（v2.5） |
| ANN-F12 | 「记号笔/马赛克/模糊/橡皮擦 支持椭圆/圆形形状」（❌/✔️） | **缺失**（马赛克/模糊只有矩形） | `SnipAnnotationCompositor.swift:34-43`（只用 `annotation.boundingRect` 做矩形裁剪） | **专业版** |
| ANN-F13 | 「双向/反向箭头」（❌/✔️） | **缺失**（只画单向箭头） | `SnipAnnotationRenderer.swift:103-120`（`drawArrow` 固定画尾部两条边） | **专业版**（v2.5） |
| ANN-F14 | 「更多箭头样式」（❌/✔️） | **缺失** | 同上，只有一种箭头 | **专业版** |
| ANN-F15 | 「文字背景填充」（❌/✔️） | **缺失** | `SnipAnnotationRenderer.swift:67-88`（只画字形，无背景矩形/描边） | **专业版** |
| ANN-F16 | 「自定义文字描边的颜色/宽度」（❌/✔️） | **缺失** | 同上 | **专业版** |
| ANN-F17 | 「旋转标注图形：免费仅文字，专业版除线条标注外都支持」 | **部分实现**（只文字可转 90°，其余不可） | `SnipAnnotation.swift:104-105`（`rotation` 只有文字用）；`SnipAnnotationRenderer.swift:81-83`（只有 `drawText` 消费 `rotation`） | 免费（文字）/ **专业版**（其余形状） |
| ANN-F18 | 「二次编辑：选中同类型已绘图形，Del 删除、Ctrl+Shift+C 复制、Ctrl+Shift+V 粘贴、Ctrl 拖拽克隆」（专业版特性 A.标注 1） | **缺失**（唯一可选中并二次操作的是文字：点选中 → 滚轮改字号 / ⌘R 旋转） | `SnipOverlayView+Annotation.swift:183-195`（只有 `.text` 走命中选中）；`SnipOverlayView.swift:82` `selectedAnnotationIndex` 只有一处写（`:189`）；`Del`/`⌘⇧C`/`⌘⇧V`/`⌃拖拽` grep 均无（附录 A g19–g21） | **专业版** |
| ANN-F19 | 「自由选中」（❌/✔️） | **缺失** | 同上，无自由选择框 | **专业版** |
| ANN-F20 | 「笔尖数量 1（免费）/ 1–5（专业版）」 | **缺失**（单一 `lineWidth`，无笔尖槽位） | `SnipAnnotationStyle.swift` 段 `SnipAnnotation.swift:34-51`（只有 `lineWidth` 一个标量）；grep `笔尖|penTips|tipCount` → **0 命中** | 免费 1 / **专业版** 1–5 |
| ANN-F21 | 「拖拽调色板以重新排序颜色」（❌/✔️） | **缺失**（固定 7 色常量） | `SnipToolBarView.swift:80`（`static let colors`）；无拖动排序实现 | **专业版** |
| ANN-F22 | 「滚轮调整颜色透明度」（❌/✔️） | **缺失**（滚轮被文字字号占用） | `SnipOverlayView.swift:237-249` | **专业版** |
| ANN-F23 | 「为不同标注形状分别记忆颜色」（❌/✔️） | **缺失**（全局一个 `currentStyle`） | `SnipOverlayView.swift:69`（`var currentStyle = SnipAnnotationStyle()`）；全仓只有 `SnipOverlayView+Annotation.swift:19` 一处赋值 | **专业版** |
| ANN-F24 | 「自定义调色板，分享调色板」（❌/✔️） | **缺失** | 同上；设置页只有 7 色单选（`SettingsCapturePane.swift:29-37,138-154`） | **专业版** |
| ANN-F25 | 高级设置 `[Annotate] auto_select_on_creation`（创建后自动选中，默认 true） | **缺失**（新建图形后 `selectedAnnotationIndex` 仍为 nil） | `SnipOverlayView+Annotation.swift:233-239`（`commitTextEditing` 只 `add`，不设选中）；`:275-284`（`handleAnnotationMouseUp` 同） | 免费（高级设置项） |
| ANN-F26 | 高级设置 `[Interface] hide_output_options`（隐藏工具条「输出选项」菜单） | **不适用**（本项目工具条没有输出选项菜单，是 4 个独立动作按钮） | `SnipToolBarView.swift:8-25`（`cancel/copy/save/pin` 四个按钮） | 免费 / 专业版 |
| ANN-F27 | 「工具条：工具切换、颜色板、线宽、空格显隐、右键完成当前图形」 | **部分实现**：工具切换 / 当前色 / 当前线宽 / 空格显隐有；**颜色板与全部线宽被折进二级面板**（一次点击变两次），右键完成当前图形缺失 | `SnipToolBarView.swift:46-48,240-263`；`SnipToolPanelView.swift:70-135`；空格 `SnipOverlayView.swift:297-301` | 免费 |
| ANN-F28 | 「对橡皮擦工具禁用二次编辑」（v2.6 选项） | **不适用**（本项目无图形二次编辑，橡皮擦只会删除） | `SnipOverlayView+Annotation.swift:296-325` | 专业版选项 |

---

## 3. 贴图域（Paste / Pin）

### 3.1 贴图快捷键（官方「只对贴图有效」表）

| 编号 | 官方行为（原文摘要） | 本项目现状 | 证据 | 官方版本归属 |
|---|---|---|---|---|
| PASTE-K01 | 「1 将贴图顺时针旋转 90 度」 | **已实现** | `Pin/PinWindow.swift:56-81`（`case "1": rotate(clockwise: true)`，另含小键盘 `18/19` 兜底） | 免费 |
| PASTE-K02 | 「2 将贴图逆时针旋转 90 度」 | **已实现** | `PinWindow.swift:75` | 免费 |
| PASTE-K03 | 「3 水平翻转贴图」 | **已实现** | `PinWindow.swift:76`；`SnipImageTransform.swift` | 免费 |
| PASTE-K04 | 「4 垂直翻转贴图」 | **已实现** | `PinWindow.swift:77` | 免费 |
| PASTE-K05 | 「5 切换灰度显示」 | **有但语义不同（键位冲突）**：本项目 `5` = **缩略图**，不是灰度 | `PinWindow.swift:78`（`case "5": toggleThumbnail()`）；`:102-110`（`toggleThumbnail` 把 `isThumbnail` 设 true 后 `setScale(0.3)`） | **专业版**（v2.8） |
| PASTE-K06 | 「6 切换反色显示」 | **缺失** | `PinWindow.swift:73-80` 无 `"6"`；grep `grayscale|invertImage|反色|灰度` → 2 命中均为菜单面板悬停气泡注释（`SystemChartDrawing.swift:81`、`MenuPanelCharts.swift:196`） | **专业版**（v2.3.2） |
| PASTE-K07 | 「Esc 隐藏标注工具条或关闭贴图窗口」 | **已实现**（关闭，可恢复） | `PinWindow.swift:57-60`（`case 53: ... closeAndReport()`） | 免费 |
| PASTE-K08 | 「Shift + Esc 销毁贴图窗口」 | **已实现** | `PinWindow.swift:59`（`if modifierFlags.contains(.shift) { destroy() }`） | 免费 |
| PASTE-K09 | 「Ctrl + W 关闭贴图窗口」 | **缺失** | `PinWindow.swift:56-81` 无 `⌘W` 分支；`canBecomeKey=true` 却没有 `performClose` / `keyEquivalent` 处理 | 免费 |
| PASTE-K10 | 「Ctrl + A 选中所有可见的贴图」 | **缺失**（无多选能力） | 见 PASTE-F24 | **专业版** |
| PASTE-K11 | 「Ctrl + Shift + C 复制纯文本（如果该贴图是由文本转换而来）」 | **缺失**（贴图窗不记录内容来源） | `PinWindow.swift` 只持有 `CGImage`（`:20-21` `currentImage`），无 `sourceText`；`SnipClipboardRenderer` 渲染后即丢弃原文（`:30-48`） | 免费 |
| PASTE-K12 | 「Ctrl + V 以剪贴板中的内容替换该贴图」 | **缺失** | `PinWindow.swift:56-81` 无 `"v"`；`SnipController+Pin.swift:12-55` 只**新建**贴图，不替换目标窗口 | 免费 |
| PASTE-K13 | 「Ctrl + Shift + P 打开首选项对话框」 | **有但语义不同**：本项目是 `⌥⇧,`（另一个独立热键） | `SnipController.swift:61-62`（`settingsCombo = kVK_ANSI_Comma + optionKey|shiftKey`）；`SnipHotKeyPreferences.swift:41-42` | 免费 |
| PASTE-K14 | 基础操作「放大镜：和截图时一样，按住 Alt 可唤出放大镜」 | **缺失**（贴图窗无放大镜） | `PinWindow.swift` 全文件无 `magnifier`/`Alt` 分支 | 免费 |
| PASTE-K15 | 基础操作「取色：和截图时一样，放大镜可见时按 C 可复制颜色值」 | **缺失** | 同上 | 免费 |
| PASTE-K16 | 常见问题「贴图要点开右键菜单才能编辑，也可以在贴图上按一下空格键」 | **缺失**（空格在贴图窗无绑定） | `PinWindow.swift:56-81`（`default: super.keyDown`） | 免费 |

### 3.2 贴图功能项（含专业版独占）

| 编号 | 官方行为（原文摘要） | 本项目现状 | 证据 | 官方版本归属 |
|---|---|---|---|---|
| PASTE-F01 | 「贴图 = 把剪贴板内容变成图片并作为窗口置顶显示」+ 窗口基类：无边框、置顶、跨 Space、全屏 App 之上、阴影与圆角 | **已实现**（四件套：`.nonactivatingPanel` + `.screenSaver` + 四项 `collectionBehavior` + `.accessory`；`hasShadow=true`） | `PinWindow.swift:30-52`（`:37` level、`:38` collectionBehavior、`:41` hasShadow）；圆角：窗口非不透明但图片本身无圆角裁剪 → **部分**（无圆角） | 免费 |
| PASTE-F02 | 「拖动贴图」（拖动移动窗口） | **已实现** | `PinWindow.swift:42`（`isMovableByWindowBackground = true`） | 免费 |
| PASTE-F03 | 「缩放贴图：滑动滚轮」 | **已实现** | `PinWindow.swift:85-91`（非 `⌃` 时 `setScale`）；`:94-99`（限幅 0.1–10） | 免费 |
| PASTE-F04 | 「缩放贴图：+ / -」 | **缺失** | `PinWindow.swift:56-81` 无 `"+"`/`"-"`；grep `plus|minus|\+\+|zoomIn` 于 Pin → 无 | 免费 |
| PASTE-F05 | 「拖动贴图窗口的边缘」改尺寸 | **缺失**（`styleMask` 无 `.resizable`，也没有自绘边条） | `PinWindow.swift:33-36`（`[\.borderless, .nonactivatingPanel]`）；grep `EWResizableWindow|resizeHandle|liveResize` → **0 命中** | 免费 |
| PASTE-F06 | 「设置贴图透明度：Ctrl + 滑动滚轮」 | **已实现** | `PinWindow.swift:85-91`（`if modifierFlags.contains(.control) { adjustAlpha(...) }`）；`:124-126`（限幅 0.1–1） | 免费 |
| PASTE-F07 | 「透明度：Ctrl + + / -」 | **缺失** | 同 PASTE-F04 | 免费 |
| PASTE-F08 | 「使贴图鼠标穿透：首选项-控制-全局快捷键-鼠标穿透开关；触发后切换光标所在贴图的穿透状态；若无贴图在光标下则取消所有贴图的穿透」 | **缺失** | grep `ignoresMouseEvents = true|setClickThrough|mouseThrough` → 1 命中，是**轻提示条**（`SnipFailureNotice.swift:37`），与贴图无关；`PinWindow` 无 `ignoresMouseEvents` 切换 | **专业版**（对比表 ❌/✔️） |
| PASTE-F09 | 「重置贴图为 100% 大小及 100% 不透明：中键单击（可自定义）」 | **缺失** | `PinWindow.swift:56-81` 无 `otherMouseDown`；右键菜单里有「不透明度 100%」但**没有重置尺寸**（`:169,181`） | 免费 |
| PASTE-F10 | 「缩略图模式：Shift + 左键双击（可自定义）」 | **有但语义不同**：缩略图绑在数字键 `5`，比例写死 30%，不是 Shift 双击 | `PinWindow.swift:78,102-110` | 免费 |
| PASTE-F11 | 「关闭单张贴图：Esc / 左键双击 / Ctrl+W；被关闭的贴图可再次被贴出，除非超过「可被恢复的已关闭贴图数」（默认建议 1，可在选项设置）」 | **部分实现**：Esc 有、右键菜单「关闭（可恢复）」有、恢复池有；**双击关闭缺失、⌘W 缺失、恢复上限硬编码 3 且无设置项** | `PinWindow.swift:57-60`；`PinWindowController.swift:11`（`maximumRecoverable = 3`）、`:181-195`（`handleClosed` 入池）、`:105-119`（`restoreMatching`）；设置页无该项（`SettingsCapturePane.swift:54-61`） | 免费 |
| PASTE-F12 | 「隐藏所有贴图：Shift+F3；再次按下显示所有；隐藏不影响已关闭贴图计数；隐藏的不会自动销毁」 | **已实现** | `SnipController.swift:63-65`（`hideAllPinsCombo = ⇧F3`）；`SnipController+HotKeys.swift:252-261`；`PinWindowController.swift:89-99`（`toggleHidden`）；`isHidden` 与 `recentlyClosed` 分离（`:17-18`） | 免费 |
| PASTE-F13 | 「销毁贴图：Shift+Esc / 右键菜单销毁；被销毁的不会再通过贴图键恢复」 | **已实现** | `PinWindow.swift:59,154-157,172`；`PinWindowController.swift:181-186`（`destroyed` 分支不入池） | 免费 |
| PASTE-F14 | 「关闭 Snipaste 时，如果已关闭的贴图没有被显示出来，它们会被自动销毁」 | **缺失**（退出时 `closeAll()` 存在但**没有任何调用方**） | grep `closeAll()` → **1 命中**，只有定义 `PinWindowController.swift:156-162`；`AppDelegate.swift:55-58` 的 `applicationWillTerminate` 只 `coordinator?.stop()` | 免费 |
| PASTE-F15 | 「贴图分组」（对比表：免费版 ✔️） | **缺失** | grep `PinGroup|pinGroup|贴图组|groupManager` → **0 命中**；`PinWindowController` 只有一个扁平 `windows` 数组（`:16`） | **免费**（对比表明确免费即有） |
| PASTE-F16 | 「贴图组管理：添加/删除/重命名/排序」（专业版特性 A.贴图 10） | **缺失** | 同上；CLI `show-group-manager` 亦无 | **专业版** |
| PASTE-F17 | 「取消/启用贴图窗口置顶」（❌/✔️） | **缺失**（所有贴图强制 `.screenSaver`） | `PinWindow.swift:37`（`level = .screenSaver`，无切换 API） | **专业版** |
| PASTE-F18 | 「自由尺寸缩略图」（❌/✔️） | **缺失**（只有固定 30%） | `PinWindow.swift:102-110` | **专业版** |
| PASTE-F19 | 「贴图裁剪」（❌/✔️） | **缺失**（贴图窗内没有框选裁剪；`PinWindowController.crop` 是「从截图捕获裁选区」的另一个东西） | `PinWindowController.swift:228-234`（`static func crop(_ captured:to:)` 是导入用）；`PinWindow` 无裁剪状态 | **专业版** |
| PASTE-F20 | 「灰度转换」（❌/✔️） | **缺失** | 同时 PASTE-K05；`SnipImageTransform.swift` 只有 rotate/mirror（57 行） | **专业版** |
| PASTE-F21 | 「反色」（❌/✔️） | **缺失** | 同上 | **专业版** |
| PASTE-F22 | 「支持虚拟桌面」（❌/✔️） | **超出官方（免费版即具备）**：`canJoinAllSpaces` 已开 | `PinWindow.swift:38` | **专业版**（我们已对齐专业版行为） |
| PASTE-F23 | 「Solo 模式：暂时只显示某个贴图，隐藏其他贴图（不会丢失）」 | **缺失** | grep `soloMode|solo` → 1 命中（`BillingVisualLogicTests.swift:59` 的无关词） | **专业版** |
| PASTE-F24 | 「多选贴图窗口：按住 Ctrl 再点击可多选，之后批量移动 / 透明度调整 / 关闭」+ `[Paste] include_active_window_for_multiselection` | **缺失** | grep `multiselect|多选贴图` → 0；`PinWindowController` 无选中集合 | **专业版** |
| PASTE-F25 | 「背景模式（透明 / 伪透明 / 暗色棋盘 / 亮色棋盘）」 | **缺失** | `PinWindow.swift:39-41`（`isOpaque=false, backgroundColor=.clear, hasShadow=true`，只有「透明」一种，且透明区域**不可点**——等价于官方「透明」而非「伪透明」） | **专业版** |
| PASTE-F26 | 「支持粘贴/拖拽网页图片（浏览器右键复制图像后贴图；直接拖拽到已有贴图）」 | **部分实现**：剪贴板里浏览器复制出的 `.png`/`.tiff` 走 `clipboardCGImage` 可贴（**未验证**浏览器具体写什么类型）；**拖拽到贴图窗完全缺失** | 剪贴板路径 `SnipController+Pin.swift:79-91`；拖拽：`PinWindow.swift` 无 `registerForDraggedTypes`（grep 命中只在 `TransferPaneView.swift:69`） | **专业版** |
| PASTE-F27 | 「输入贴图尺寸/缩放比例」 | **缺失** | `PinWindow.swift` 无输入框；`setScale` 只有滚轮入口（`:94`） | **专业版** |
| PASTE-F28 | 「可编辑的颜色卡片」（❌/✔️） | **缺失**（色卡能贴出，但改不了颜色值） | `PinWindowController.swift:74-85` `pinColor` 存在但**全仓无调用**（附录 A g22）；实际的色卡来自 `SnipClipboardRenderer.renderColor`（`:81-97`，纯静态绘制、无编辑回调） | **专业版** |
| PASTE-F29 | 免费色卡：「颜色值（RGB/HEX）→ 色卡贴图」 | **已实现** | `SnipClipboardClassifier.swift:25,36-76`（解析颜色）；`SnipController+Pin.swift:48-54`；`SnipClipboardRenderer.swift:81-97` | 免费 |
| PASTE-F30 | 「右键菜单：复制、另存、旋转、透明度、置顶开关、销毁」 | **部分实现**：复制 / 另存 / 旋转 / 水平镜像 / 缩略图 / 不透明度 100% / 关闭 / 销毁有；**缺垂直镜像、缺置顶开关、缺透明度连续调节** | `PinWindow.swift:161-183` | 免费（置顶开关为专业版） |
| PASTE-F31 | 高级技巧「对齐贴图窗口到其他贴图或程序窗口：按住 Shift 再拖动，差不多对齐后释放」+ `[Paste] magnetic_attach_threshold`（默认 20×DPI） | **缺失** | `PinWindow.swift:42`（`isMovableByWindowBackground`，无 Shift 吸附）；grep `magnetic|吸附` → 0 | 免费 |
| PASTE-F32 | 高级设置 `[Paste] disable_frame_resize` / `force_html_wrap` | **不适用 / 部分**：前者因本项目没有边条缩放而不适用；后者（HTML 强制换行）当前渲染已按最大宽度换行 | `SnipClipboardRenderer.swift:101-123`（`boundingRect(width: maximumTextWidth)`） | 免费 |
| PASTE-F33 | 常见问题「取消贴图的平滑缩放（改善文字缩放后的清晰度）」 | **缺失** | `PinWindow.swift:49`（`imageScaling = .scaleAxesIndependently`，无插值开关） | 免费 |
| PASTE-F34 | 常见问题「贴图无法拖出屏幕上边界」的处理 | **部分实现**：有屏幕变化后的回拉（`clampToScreens`），但**没有拖动过程中的边界钳制** | `PinWindowController.swift:30-44,136-150`；`PinWindow.swift` 无 `constrainFrameRect` 覆写 | 免费 |
| PASTE-F35 | 「关闭或销毁多个贴图前增加二次确认」（v2.10.7 / v2.11） | **缺失** | `PinWindowController.swift:156-162`（`closeAll` 直接关，且无调用方）；单张关闭无确认 | 免费（新版本行为） |

---

## 4. 内容源（把剪贴板变贴图）

| 编号 | 官方行为（原文摘要） | 本项目现状 | 证据 | 官方版本归属 |
|---|---|---|---|---|
| CONTENT-01 | 「剪贴板中复制有图像」 | **已实现** | `SnipController+Pin.swift:14,22,79-91`（ImageIO + 像素守卫） | 免费 |
| CONTENT-02 | 「剪贴板中有文件路径：文件是图片→把图像贴出；图像贴出后再贴→把文件路径当文本贴出；文件不是图片→把路径当文本贴出；可在选项里选择不要把文件路径转成图片」 | **部分实现**：图片文件→贴图像（受像素守卫约束）；非图片→贴图标+文件名。**「再贴一次降级为纯文本路径」与「选项开关」都没有** | 图片文件 `SnipController+Pin.swift:83-89`；非图片 `SnipClipboardRenderer.swift:52-77`（图标 + `lastPathComponent`）；降级/开关 grep `filePathAsText` → 0 | 免费 |
| CONTENT-03 | 「剪贴板中有文字：纯文本 / HTML 文本」 | **已实现** | `SnipClipboardClassifier.swift:26-32`；`SnipClipboardRenderer.swift:30-48,101-123` | 免费 |
| CONTENT-04 | 「文字贴图：自动换行、最大宽度、字号、复制回纯文本」 | **部分实现**：换行与最大宽度（480pt）有、字号固定 14 不可调；**「复制回纯文本」⌘⇧C 缺失** | `SnipClipboardRenderer.swift:11`（`maximumTextWidth = 480`）、`:31-35`（`font 14`）；复制回纯文本见 PASTE-K11 | 免费 |
| CONTENT-05 | 「颜色信息：RGB 3 个 0~255 整数或 3 个 0~1 的小数；HEX 以 # 开头的合理色值」 | **部分实现**：支持 `#RGB`/`#RRGGBB`/`rgb()`/`rgba()`；**不支持 0~1 小数三元组、不支持不带 `#` 的裸十六进制** | `SnipClipboardClassifier.swift:36-76`（`:40` 要求 `hasPrefix("#")`，`:68-71` 把分量 clamp 到 0–255 后取整） | 免费 |
| CONTENT-06 | 「图像贴出后再贴，会把文件路径当做文本贴出」 | **缺失**（同 CONTENT-02） | 同上 | 免费 |
| CONTENT-07 | 命令行 `paste --plain TEXT` / `paste --html TEXT` / `paste --files ...` / `--pos X Y` | **缺失**（无 CLI） | 见 SYS-F02 | 免费（`--pos` 等贴图参数属命令行扩展） |

---

## 5. 系统集成与周边

| 编号 | 官方行为（原文摘要） | 本项目现状 | 证据 | 官方版本归属 |
|---|---|---|---|---|
| SYS-F01 | 「偏好设置窗（截屏/贴图/标注/控制/外观多页 + 持久化）」 | **已实现**（统一设置窗「截图与贴图」页：默认颜色 / 线宽 / 贴图默认不透明度 / 复制后自动保存 / 快速保存目录 / 6 个热键录制） | `Settings/SettingsCapturePane.swift:54-176`；入口 `Snip/SnipSettingsDelegate.swift`（10 行协议）+ `AppCoordinator+Snip.swift:33-37` | 免费 |
| SYS-F02 | 「命令行选项」：`snip` / `snip --area X Y W H` / `snip --size W H` / `snip --full` / `snip --last` / `snip --active-window` / `snip --active-screen` / `snip --custom` / `--delay TIME` / `--shadow`/`--no-shadow` / `-o pin|clipboard|ocr_clipboard|FILE_NAME|quick-save|file-dialog|printer|no-auto-save|silent|success|exec(COMMAND)` / `--hold` / `--block`；`paste` 系列；`show-images`/`hide-images`/`toggle-images`/`create-group`/`switch-group`/`empty-group`/`show-group-manager`/`no-click-through`/`toggle-click-through`/`show-tray-menu`/`whiteboard`/`transparent-whiteboard`/`external`/`pick-color`/`barcode-scan`/`barcode-decode FILE`/`paste-as-image`/`paste-as-plain-text`/`switch-group-prev`/`disable-hotkeys`/`enable-hotkeys`/`toggle-hotkeys`/`disable-hot-corners`/`enable-hot-corners`/`toggle-hot-corners`/`clear-snip-history`/`open-preferences`/`docs`/`exit`/`--config` | **缺失（整域）**：完全没有任何对外命令入口 | grep `CommandLine.arguments|ProcessInfo.processInfo.arguments` 于 `NetworkMonitor/Sources` → 5 命中：`Debug/PanelOpenProbe.swift:39`（DEBUG 取证）、`Scripts/clipboard-permission-probe.swift:27`、`Scripts/generate-icon.swift:11`、`TestRunner/main.swift:9,15`（`--harness-index`/`--number-unit-table`，测试用）。**无一处是产品 CLI**；`main.swift`（12 行）只 `NSApplication.shared` + `app.run()` | 免费（「基础」）/ **专业版**（「丰富」+ 粗体项：`--keep_aspect_ratio`、`--shadow`/`--no-shadow`、`-o ocr_clipboard`、`-o no-auto-save`、`-o silent`、`--hold`、`--block`、`show-group-manager`、`whiteboard --color`、`--active-screen`、`transparent-whiteboard`、`external`、`pick-color`、`barcode-scan`、`barcode-decode`、`paste-as-image`、`paste-as-plain-text`、`switch-group-prev`、`disable/enable/toggle-hotkeys`、`disable/enable/toggle-hot-corners`、`clear-snip-history`、`open-preferences`、`docs`、`exit`） |
| SYS-F03 | 「显示器增删、分辨率变化、跨 Space 的贴图存活处理」 | **已实现** | `PinWindowController.swift:30-44`（`didChangeScreenParametersNotification`）、`:136-150`（`clampToScreens`）；跨 Space `PinWindow.swift:38` | 免费 |
| SYS-F04 | 「文字识别（OCR）」（❌/✔️；v2.11 起支持腾讯与 OCR.space 接口） | **缺失** | grep `VNRecognize|Vision|OCR|ocr` 于 `NetworkMonitor/Sources` → **0 命中** | **专业版**（v2.11） |
| SYS-F05 | 「识别二维码/条形码」+ `barcode-scan` / `barcode-decode FILE` | **有但语义不同**：本项目的二维码能力是**局域网互传的扫码接收**（相机扫码）与**二维码生成**，不是「识别屏幕或图片上的码并把结果复制」 | 生成 `NetworkMonitorCore/Transfer/Service/QRCodeGenerator.swift:6-20`；接收 `Transfer/TransferScanSheet.swift:6,108-146`、`TestRunner/ScanTests.swift:160-195`；grep `barcode-scan|barcode-decode` → 0 | **专业版**（v2.8） |
| SYS-F06 | 「为任意功能绑定全局快捷键（专业版）」/ 免费版只能绑少数几个 | **部分实现**：6 个固定动作（截图/贴图/延时截图/隐藏贴图/打开设置/白板）都可录制组合键并落盘；**不能绑定任意命令，也不能绑同一命令的多条** | `SnipHotKeyPreferences.swift:11-52`（6 个 action 与默认组合）；`SnipController+HotKeys.swift:11-30,59-68`（注册/重绑）；录制控件 `SettingsCapturePane.swift:156-176` | 免费（少数）/ **专业版**（任意） |
| SYS-F07 | 「在指定程序忽略某全局快捷键（支持模糊匹配）」 | **缺失**（截图链路没有忽略名单；剪贴板链路有 `ignoredBundleIDs`，但那不是截图热键） | grep `忽略程序|ignoreList|ignoredApps|白名单程序` → 3 命中，全在 `Clipboard/ClipboardPreferences.swift:61,149-150` | **专业版** |
| SYS-F08 | 「屏幕触发角：鼠标移到四角执行指定功能」+ `disable/enable/toggle-hot-corners` | **缺失** | grep `hotCorner|触角|triggerCorner` → **0 命中** | **专业版** |
| SYS-F09 | 「自定义托盘图标的鼠标动作（左/中/右键各执行什么命令）」 | **有但语义不同**：左键=开合面板、右键=固定菜单（设置…/退出），中键无绑定，三者都不可自定义 | `MenuBarManager.swift:117-135`（`sendAction(on: [.leftMouseUp, .rightMouseUp])`）、`:137-155`（固定菜单） | **专业版** |
| SYS-F10 | 「自定义放大镜样式 / 完全隐藏放大镜」 | **缺失**（放大镜常驻、样式写死 120pt/15pt 跨度、网格固定） | `SnipOverlayView+Drawing.swift:76-77`（`magnifierSide = 120`、`magnifierSpan = 15`）；无开关 | **专业版** |
| SYS-F11 | 「主题色跟随系统主题」 | **未验证**：截图工具条与二级面板是写死的深色（`black 0.82`），不随系统；贴图本身无 UI。是否算「跟随系统」无法从代码判定为对齐 | `SnipToolBarView.swift:157-159`、`SnipToolPanelView.swift:103-104` | **专业版** |
| SYS-F12 | `[Output] auto_alpha_channel_removal`（保存时若无半透明像素则移除 alpha 通道减小体积） | **缺失** | `SnipFileWriter.swift:15-26`（`CGImageDestinationAddImage(destination, image, nil)`——properties 传 `nil`，不做通道分析） | 免费 |
| SYS-F13 | 常见问题「输出的图片质量：-1 自动 / 0 最低 / 100 最高（默认 -1）」 | **缺失**（只写 PNG，无质量参数、无格式选择） | `PinWindowController.swift:211`、`SnipController+Export.swift:85`（`allowedContentTypes = [.png]`） | 免费 |
| SYS-F14 | `[Misc] uppercase_hex_color`（Hex 颜色值用大写） | **超出官方默认（恒为大写、无开关）** | `SnipPixelSampler.swift:19-21`（`String(format: "#%02X%02X%02X", ...)` 恒大写） | 免费（高级设置项，默认 false） |
| SYS-F15 | `[Misc] double_tap_interval`（键盘按键双击间隔，默认 400ms） | **缺失** | grep `double_tap|双击间隔` → 0 | 免费 |
| SYS-F16 | `[Misc] software_metadata`（保存时写入 Snipaste 元数据，仅专业版可改） | **缺失** | 同 SYS-F12（properties 为 nil） | **专业版** |
| SYS-F17 | `[Log]` 日志文件/刷新/轮转设置 | **超出官方（自成体系）**：本项目有统一 `LoggingService`（OSLog category）+ `LogRedaction`，无 ini 可调项 | `NetworkMonitorCore/Infrastructure/Logging/Loggers.swift`；调用点遍布 `SnipController.swift:27` 等 | 免费（高级设置项） |
| SYS-F18 | `[General] gpu_acceleration`（改善马赛克/高速模糊/阴影绘制效率） | **未验证**：马赛克/模糊走 Core Graphics（`SnipMosaicProcessor.swift`），是否有 GPU 加速由系统决定，无显式开关 | `SnipMosaicProcessor.swift:19-50` | 免费（v2.8） |
| SYS-F19 | `[General] hide_tray_icon` | **不适用**：菜单栏 App 常驻状态栏，没有「隐藏图标后靠 Ctrl+Shift+P 唤出首选项」这套语义 | `MenuBarManager.swift:117-126` | 免费（高级设置项） |
| SYS-F20 | `[General] process_priority` | **不适用**（文档注明「此选项为 Windows 独占」） | — | Windows 独占 |
| SYS-F21 | `[Hotkey2] exchange_wasd_and_arrow_keys` / `allow_simple_hotkeys` | **缺失 / 部分**：前者无开关（WASD 与方向键语义固定）；后者：`HotKeyRegistry` 直接用 Carbon `RegisterEventHotKey`，未做「单键禁止」判断，但所有默认组合都带修饰键 | `HotKeyRegistry.swift:38-57`；`SnipHotKeyPreferences.swift:30-46` | 免费（高级设置项） |

---

## 6. 本项目已有但语义不同（单列）

> 这一节只收「名字/键位对得上、行为对不上」的项。真正的缺失在 §1–§5 已列，不重复。

| 官方项 | 官方语义 | 本项目语义 | 为什么不同（可核查的事实） | 影响 |
|---|---|---|---|---|
| `Tab` | 在「检测窗口」与「检测界面元素」之间切换 | 只在「窗口检测 开/关」之间切 | 本项目没有界面元素检测（SNIP-F14），所以 Tab 的另一半不存在（`SnipKeyCommand.swift:101`） | Tab 没提供官方那半个功能，却占掉了官方语义 |
| `⌘⇧Z` | 移除所有标注（**无法再恢复**） | **重做**下一个标注 | `SnipKeyCommand.swift:131`（`case "z" where .shift: return .redo`）；`SnipOverlayView.swift:327-329` | 危险：用户想「清空」会得到「重做」；且本项目没有「清空全部」入口 |
| `⌘Y` | 恢复下一个标注 | 未绑定（重做走 ⌘⇧Z） | 同上 | 官方习惯迁移不过来 |
| `右键单击`（截图态，非编辑） | 重新设置截屏区域 / 中止截屏（两义） | 一律中止整次截图 | `SnipOverlayView.swift:170-176,232-234` | 少一个「只重设不回退」的中间态 |
| `右键单击`（编辑标注时） | 结束当前图案 | 取消整次截图（图形丢弃） | 同上 | 画到一半想收笔会丢整张截图，是本轮最刺眼的行为差异之一 |
| `Alt` | 召唤放大镜（默认自动隐藏） | 放大镜常驻显示（选区成立后反而隐藏）；Alt 无绑定 | `SnipOverlayView+Actions.swift:182-184`；`SnipKeyCommand.swift` 全表无 option 分支 | 与官方「按需出现」的心智模型相反 |
| `Shift`（放大镜可见时） | 切换颜色格式 | 任意按下就切 hex↔RGB，且同时被「缩小选区」占用 | `SnipOverlayView.swift:340-345`（`flagsChanged`）vs `SnipOverlayView+Actions.swift:139-140` | 一次 Shift 同时触发两件事 |
| `W A S D` | 移动**鼠标指针** 1 像素 | 移动**选区** 1 像素 | `SnipKeyCommand.swift:111-114` → `SnipOverlayView+Actions.swift:142` `state.move` | 同键不同对象；官方另有「按住左键 + WASD」才是调区域（本项目无，SNIP-F07） |
| `⌃↑←↓→` / `⇧↑←↓→` | 扩大/缩小**对应那一条边** | 四边同时外扩/内缩（保持中心） | `SnipOverlayView+Actions.swift:137-140` → `SnipSelectionState.swift:109-120`（`insetBy`） | 逐边微调做不到，只能整体缩放 |
| `5`（贴图态） | 灰度显示切换 | **缩略图**（30%） | `PinWindow.swift:78,102-110` | 键位被占，灰度无处可放（PASTE-K05/F20） |
| `Shift + 左键双击`（贴图） | 缩略图模式 | 不存在（缩略图在 `5`） | 同上 | 同 PASTE-F10 |
| `F1` / `F3` 默认热键 | 截图 / 贴图 | `⌃⇧S` / `⌃⇧V` | `SnipHotKeyPreferences.swift:34-37`（注释：无修饰单键在 macOS 27 与系统媒体键抢通道，实测 3 次只到 1 次） | 这是**故意的偏离**，有实测依据；旧默认值迁移由 `SnipHotKeyMigration` 处理（`SnipHotKeyComboResolver.swift:69-76`） |
| `⌃⇧P` | 打开首选项 | `⌥⇧,` | `SnipController.swift:61-62` | 键位不同、功能等价 |
| 点击托盘图标 | 左键=开始截图；中键=贴图 | 左键=开合面板；右键=菜单；中键无绑定 | `MenuBarManager.swift:117-135` | 菜单栏 App 的必然差异（面板是主界面），但「点一下就截图」的快捷入口因此没有 |
| 反引号 `\` 或 `!` | 显隐捕获的鼠标指针 | 只有反引号 | `SnipKeyCommand.swift:97` vs `:110-118` | 少一个备用键 |
| 截图记录 `,` `.` | 回放**截图图像** | 回放**选区矩形** | `SnipController.swift:93-105`（存的是 `CGRect`）、`SnipSelectionHistoryCoding.swift:9` | 语义还在（都是「上次框哪儿」），但官方是「重看那张图」，本项目是「再框同一块」 |
| 「可被恢复的已关闭贴图数」默认建议 1 | 用户可设 | 硬编码 3，不可设 | `PinWindowController.swift:11` | 恢复池更大（更好用），但没有官方那个「不想要就关掉、关掉能反悔」的调参手感 |
| 颜色值输出格式 | 有 `uppercase_hex_color` 开关，默认小写 | 恒大写 | `SnipPixelSampler.swift:19-21` | 与默认值相反，但业内常见 |
| 贴图背景模式 | 四种可选 | 只有「透明」（透明区域不可点，等价官方「透明」；官方默认更接近「伪透明」） | `PinWindow.swift:39-41` | 点到透明区拖不动窗口，与官方「伪透明」手感不同 |
| 工具条颜色板/线宽 | 一级工具条上直接可点 | 收进「更多」二级面板（点两次） | `SnipTool.swift:30-37`（`primary`/`overflow`）；`SnipToolBarView.swift:240-263` | 高频改色多一次点击；换来工具条从 ~800pt 收到 `preferredWidth`（`SnipToolBarLayout.swift`） |
| 贴图「双击关闭」 | 左键双击 | 无（双击无绑定，中键也无绑定） | `PinWindow.swift:56-81`；`SnipOverlayView.swift:188-192` 的双击只属于**截图选区**（=复制） | 截图里双击=复制已对齐官方；贴图里双击=关闭没做 |
| 白板模式 | 纯白 + 透明白板两种；Esc 退出被禁用；工具条需空格唤出 | 只有纯白；Esc 正常退出；工具条遵循常规空格显隐 | `SnipController+HotKeys.swift:203-239` | 大方向一致，细粒度不同 |

---

## 7. 优先级清单

评分三维，每维 1–5 分（5 最好/最省）：
- **U 高频**：官方文档把它写成默认行为/默认快捷键，或常见问题里被单独回答 → 用户每天会碰。
- **C 成本**：按官方描述的行为从零实现的工作量，5 = 半人日内，1 = 5 人日以上。**人日是我按官方描述自己估的**，不是旧文档口径。
- **D 依赖**：5 = 无前置依赖、独立可交付；1 = 要先有别的域（如先有 CLI 才能做 CLI 绑定）。

### P0 —— 这一轮就该做（12 条，合计 ≈13.5 人日）

| # | 项 | 官方编号 | U | C | D | 人日 | 一句话理由 |
|---|---|---|---|---|---|---|---|
| P0-1 | 右键「结束当前标注」与「中止截图」分离：非编辑态右键=中止，编辑态右键=收笔 | ANN-K05 / SNIP-K13 | 5 | 5 | 5 | 0.5 | 现在画到一半按右键会**丢掉整张截图**，是当前最刺眼的行为偏差 |
| P0-2 | 恢复 `⌘Y` = 重做；把「清空所有标注」挪到独立键位（`⌘⇧Z` 归还官方语义，清空用 `⌘⌫`） | ANN-K03 / ANN-K04 | 5 | 5 | 5 | 0.5 | 官方 `⌘⇧Z` 是「清空且不可恢复」，我们是「重做」——语义相反且没有清空入口 |
| P0-3 | 贴图窗补 `⌘W` 关闭、左键双击关闭、中键重置 100%/100% | PASTE-K09 / PASTE-F09 / PASTE-F11 | 5 | 5 | 5 | 0.5 | 三条都是官方默认行为；缺了之后鼠标党在贴图窗里只能右键 |
| P0-4 | 贴图窗补 `+`/`-` 缩放与透明度双键，右键菜单补垂直镜像 | PASTE-F04 / PASTE-F07 / PASTE-F30 | 4 | 5 | 5 | 0.5 | 键盘用户改尺寸/透明度的通路目前完全不存在 |
| P0-5 | 画笔粗细：`[` `]` 与 `1` `2`（编辑模式） | ANN-K01 | 5 | 4 | 5 | 1 | 官方把「滚轮/数字/方括号」列为默认调粗细方式，我们只能点二级面板 |
| P0-6 | Shift 标注约束（矩形→正方形、椭圆→圆、直线/箭头→水平·垂直·45°） | ANN-K17 | 5 | 3 | 4 | 1.5 | 高级技巧页视觉收益最高的一条；只在拖拽时读一次修饰键 |
| P0-7 | 图层命中后的二次编辑最小集：`Del` 删除选中图形 | ANN-F18 | 4 | 3 | 4 | 1.5 | 画错的图形现在只能橡皮擦点掉；`Del` 是最低成本的二次编辑 |
| P0-8 | 画笔透明度入口（颜色按钮 → alpha 滑杆 0–255） | ANN-K16 | 4 | 4 | 5 | 1 | 模型已有 `alpha` 字段（`SnipAnnotation.swift:10-16`），只缺 UI |
| P0-9 | 虚线样式切换入口（工具条或二级面板加一档） | ANN-F11 | 3 | 5 | 5 | 0.5 | 渲染已实现 `setLineDash`（`SnipAnnotationRenderer.swift:25-27`），只差一个开关，白捡 |
| P0-10 | 贴图内容源补 `⌘⇧C` 复制纯文本（贴图记录来源文本） | PASTE-K11 / CONTENT-04 | 4 | 4 | 4 | 1 | 文字贴图是目前最常用的贴图类型，复制回纯文本是它的标配出口 |
| P0-11 | 贴图「再贴降级为路径文本」+ 图片/非图片分支的偏好开关 | CONTENT-02 / CONTENT-06 | 3 | 4 | 4 | 1 | 官方明确写了两段语义（先图后路径），现在只做了第一段 |
| P0-12 | 关窗恢复上限改为偏好项（默认 1，用户可调）并在设置页暴露 | PASTE-F11 | 3 | 5 | 5 | 0.5 | 硬编码 3 且无设置项（`PinWindowController.swift:11`），是「随时可调」的官方口径 |

**P0 合计约 13.5 人日**（不含测试与联调，按单个熟练 macOS 工程师有效工程日估）。

### P1 —— 下一轮（12 条，合计 ≈22 人日）

| # | 项 | 官方编号 | 人日 | 理由 |
|---|---|---|---|---|
| P1-1 | 贴图组（创建/切换/清空/组管理面板）+ `create-group` 等命令 | PASTE-F15/F16 | 4 | 官方**免费版即提供**，是它「做剪贴板管理」的主用法；实现面大（分组模型 + 面板） |
| P1-2 | 多选贴图 + 批量移动/透明度/关闭 | PASTE-F24 | 3 | 与贴图组同源（选择集合），依赖 P1-1 的分组数据结构 |
| P1-3 | 贴图边缘拖拽改尺寸 + 自由尺寸缩略图 | PASTE-F05/F18 | 2.5 | 官方免费版有边条缩放；现在只有滚轮等比 |
| P1-4 | 背景模式四态（透明/伪透明/暗色棋盘/亮色棋盘）+ 置顶开关 | PASTE-F25/F17 | 3 | 「伪透明」是官方手感核心：透明区可点才拖得动 |
| P1-5 | 二次编辑完整集（`⌘⇧C`/`⌘⇧V`/⌃拖拽克隆/⌘⇧ 缩放） | ANN-F18/F19 | 3 | 依赖 P0-7 的选择模型 |
| P1-6 | 灰度 `5`、反色 `6`（并把缩略图迁到 Shift 双击） | PASTE-K05/K06/F20/F21 | 1.5 | 键位冲突必须先解掉 |
| P1-7 | 截图记录改为存图像（`,``.` 回放真实截图）+ 容量设置 | SNIP-F05/F29 | 3 | 官方语义是「重看那张图」；要落盘缩略图并管容量 |
| P1-8 | 延时截屏可选时长 + 倒计时提示 | SNIP-F10 | 1.5 | 现在只有固定 3 秒且无反馈 |
| P1-9 | 刷新截图 `F5`（保持已有标注） | SNIP-K07 | 1.5 | 专业版高频项，依赖 P1-7 的历史记录 |
| P1-10 | 鼠标穿透开关（全局热键切换光标下贴图） | PASTE-F08 | 1.5 | 官方与透明度联用的固定搭配 |
| P1-11 | 屏幕触发角（四角动作 + 三组 CLI 开关） | SYS-F08 | 2 | 官方推荐用法「左上/右上显示隐藏全部贴图」 |
| P1-12 | 输出质量/格式、alpha 通道自动剥离、PNG 元数据开关 | SYS-F12/F13/F16 | 1.5 | 保存链路已集中在一个 27 行文件里，改造面小 |

### P2 —— 可暂缓（12 条，合计 ≈27 人日）

| # | 项 | 官方编号 | 人日 | 说明 |
|---|---|---|---|---|
| P2-1 | 界面元素检测（AX 粒度）+ Tab 切窗口/元素 + 滚轮切父/子 | SNIP-F14 | 6 | 高风险（AX 权限、跨 App 稳定性）；官方免费版就有，但要 6 人日以上 |
| P2-2 | OCR 文字识别（Vision + `-o ocr_clipboard`） | SYS-F04 | 3 | 专业版；Vision 可做，但要处理多语言与版面 |
| P2-3 | 命令行选项整域（`snip/paste/show-images/…`） | SYS-F02 | 6 | 单独立项；Mac 版还要求 App 能带参启动 |
| P2-4 | 任意命令绑全局热键 + 忽略程序列表 | SYS-F06/F07 | 4 | 依赖 P2-3（命令必须先存在） |
| P2-5 | 圆角矩形截图 / 圆角矩形标注 / 双向箭头 / 更多箭头样式 | SNIP-F16 / ANN-F10 / ANN-F13/F14 | 2.5 | 纯样式，视觉收益中 |
| P2-6 | 序号标注（自动递增、`+`/`-` 调） | ANN-F08 | 1.5 | 教程类截图高频 |
| P2-7 | 放大镜标注（圆内放大局部） | ANN-F09 | 2 | 专业版；要单独一个图元 + 底图重采样 |
| P2-8 | 贴图裁剪 + 颜色卡片可编辑 | PASTE-F19/F28 | 2 | 依赖 P1-4 的裁剪/编辑窗口结构 |
| P2-9 | Solo 模式 | PASTE-F23 | 1 | 与隐藏全部互补 |
| P2-10 | 拖拽网页图片到贴图 + 联网下载 | PASTE-F26 | 2.5 | 需网络权限与失败态设计 |
| P2-11 | 记号笔（独立透明度 + 独立笔尖） | ANN-F04 | 1.5 | 与画笔差异只在透明度策略 |
| P2-12 | 带阴影/边框输出 `--shadow` | SNIP-F24 | 2 | 依赖 P2-3 或独立工具条开关 |

**估算法说明**：以上人日只算「按官方描述把行为做出来」的编码与自测，不含视觉打磨与多语言；与旧文档的 105.5 人日口径**不是同一套**（旧口径按「完整重做一遍 Snipaste」分档，本表按「逐项增量补齐」估）。

---

## 8. 本轮已确认实现的对照自证（上一轮刚修的五件事 → 官方行为）

> 这一节的目的：证明「我们已经修过的东西」不是自说自话，而是**能对到官方文档的某一条行为**，并说清我们比官方做得更多还是仍不如。
> 每条给：我们做了什么（file:line）→ 官方对应条目 → 结论（**对齐 / 超出 / 仍不如**）→ 可复核的证据（测试断言 / 取证脚本 / 提交）。

### 8.1 坐标偏移（「框选 A 截到 B」）

**我们做了什么**
1. 像素尺寸不再信 `CGDisplayPixelsWide`，改用 `CGDisplayCopyDisplayMode` 的 `pixelWidth`（`ScreenCaptureService.swift:30-40`，注释写明「本机实测 macOS 27 的 2x 屏返回点数 1512 而非像素 3024」）。
2. 裁剪缩放比一律以「捕获图实际像素 ÷ 屏幕点」推导，Core 不 import AppKit（`SelectionGeometry.swift:51-73` 的 `pixelRect`）。
3. 覆盖层本地坐标 ↔ 全局 CG 坐标双向换算收进纯函数（`SelectionGeometry.swift:35-49`）。
4. 回归测试 `TestRunner/SnipGeometryTests.swift`（20 条断言）。

**官方对应**：
- `更新日志.md` v2.8 `[Mac] 支持多屏截图`、v2.7.1 `[Mac] 修复在扩展屏上回放截图历史出现错位` —— 说明官方同样把「多屏 + Retina 下的坐标错位」当成一级缺陷反复修。
- `专业版.md` 专业版专有项 `切换截屏尺寸单位 (px/dip)`（SNIP-F19）说明官方**明确区分** px 与 dip 两套口径——这正是本项目踩的坑。

**结论：对齐**（都做到了「点坐标 → 像素坐标」的正确换算）。**仍不如**：没有 px/dip 单位切换（SNIP-F19 缺失），用户看不到自己的选区到底是多少像素。

**复核方式**：`git show 1708543`（含 `SelectionGeometry.swift`、`SnipGeometryTests.swift`）；实机取证 `Debug/SnipCropProbe.swift`（`NM_SNIP_CROP_PROBE`，逐点比对裁出来的像素）。

### 8.2 闪屏（按完截图键屏幕闪一下）

**我们做了什么**
1. 抓屏**先于**抢前台：注释写明两条因果（先 activate 会让原 App 退场、popover 收起，抓到的就是背景；两帧之间的空白=闪一下）（`SnipController.swift:147-171`）。
2. 覆盖层以 `alphaValue = 0` 上屏（照样能成为 key window），**首帧真正画进窗口后**再由 `onFirstFrameRendered` 淡入 80ms（`SnipOverlayWindow.swift:69-103`；首帧钩子在 `SnipOverlayView+Actions.swift:186-191`）。
3. 拿不到绘图上下文时不早退，而是把重绘排到下一轮主循环（有上限）（`SnipOverlayView+Actions.swift:150-158`、`SnipOverlayView.swift:83-87`）。
4. 首帧超时 400ms 兜底：真的画不出来也强制可见（注释原话「宁可闪一下，也不能是一片看不见的覆盖层」）（`SnipOverlayWindow.swift:84-89`）。

**官方对应**：
- 官方文档**没有任何「防闪屏 / 首帧」条目**——这是客户端实现细节，官方没写。
- 相关语义：`基础操作.md`「任何时刻有其他程序的窗口被激活（可在选项窗口关闭此行为）」——官方把「前台切换」当一等公民讨论。

**结论：超出官方**（官方无此承诺；我们把空白帧消掉了）。**仍不如**：没有实现「别的程序被激活就取消截图」（SNIP-F04 部分实现）。

### 8.3 工具条二级面板

**我们做了什么**
1. 一级工具条只留 4 个高频工具 + 当前色 + 当前线宽 + 4 个动作按钮；其余 6 个工具与全部颜色/线宽收进「更多」二级面板（`SnipTool.swift:30-37` 的 `primary`/`overflow`；`SnipToolBarView.swift:46-48,240-263`）。
2. 面板贴着触发按钮弹出、上方放不下就翻到下方、点面板外即收起（`SnipOverlayView+Annotation.swift:26-52,88-92`；`SnipOverlayView.swift:177-183`）。
3. 宽度与按钮位置由**同一份** `SnipToolBarLayout.plan` 计算，根治「右侧多 17pt 空白」（`SnipToolBarLayout.swift:6-11,67-112`）；面板排布同理（`:114-161`）。
4. 回归测试 `SnipToolBarLayoutTests.swift`（49 条断言）。

**官方对应**：
- `专业版.md` 专业版项 `自定义工具条调色板的颜色数量`（v2.5.2）与 `拖拽调色板以重新排序颜色`——官方把「工具条上的颜色板」当直接可点的一等控件。
- `常见问题.md`「选项太多了…几乎每个选项都有悬停提示」反映官方倾向「全摆出来 + 悬停解释」。

**结论：方向与官方不同但本地更优**（官方一级工具条全摆，依赖更大屏宽；我们还有网速/Token/系统面板要抢空间，选择收进二级面板）。**仍不如**：官方一级工具条上**颜色板与线宽直接可点**，我们要两次点击；官方「笔尖 1–5 各带粗细」我们没有（ANN-F20）。

**复核方式**：`git show 5bd699c`（+568/−65，含 `SnipToolPanelView.swift` 136 行新建、`SnipToolBarLayout.swift` 新建）；只读快照 `Debug/SnipToolBarSnapshot.swift`。

### 8.4 快捷键持久化（自定义后被还原）

**我们做了什么**
1. 判定「用户设置过没有」改为**看存储里有没有这个键**（`object(forKey:) != nil`），不再用 `keyCode > 0`——因为 `kVK_ANSI_A = 0` 是合法键码，⌘⌥A 会被判成「没设置过」然后被默认值永久覆盖（`SnipHotKeyComboResolver.swift:38-77`）。
2. **读路径只读不写**：存储缺键时只返回 `defaultCombo`，绝不回写（`:45-48`；实现 `SnipHotKeyPreferences.swift:62-91`）。
3. 只有命中旧默认值白名单（`didMigrate`）才回写一次，属于迁移而非补默认（`SnipHotKeyMigration.swift`）。
4. 录制成功后「先注册、注册成功才落盘」（`SnipController+HotKeys.swift:59-68`），注册失败变红不落盘（`SettingsCapturePane.swift:163-171`）。
5. 回归测试 `SnipHotKeyPreferencesTests.swift`（24 条断言）。

**官方对应**：
- `专业版.md`：免费版「只能为少数几个功能指定全局快捷键」，专业版「可以为任意功能指定」；`高级设置.md` `[Hotkey2] allow_simple_hotkeys` 说明官方也区分「简单键 / 组合键」两类注册口径。
- `更新日志.md` v2.11.3 `[专业版] 支持自定义部分应用内快捷键`。

**结论：对齐**（都支持录制并持久化 + 冲突提示）。**仍不如**：官方专业版能绑**任意命令**（含命令行参数），我们只有 6 个固定动作（SYS-F06 部分实现）；也没有「忽略程序列表」（SYS-F07 缺失）。

**复核方式**：`git show 84f0f66`（"快捷键自定义后被还原——A 键 keyCode 0 被当成未设置"）。

### 8.5 菜单栏 / Dock / 状态栏层级识别（自家面板也要能被框到）

**我们做了什么**
1. 层级**白名单显式列举** 0（普通窗口）/ 20（程序坞）/ 24（菜单栏）/ 25（状态栏项），其余层一律不参与（`SnipWindowInfo.swift:9-36`）。
2. 系统层级不受 `minimumSide` 20pt 门槛限制（状态栏项实测可能只有 30×24）（`SnipWindowInfo.swift:98-107`）。
3. 自家进程**不再整段排除**：只有层级 ≥1000（覆盖层量级）的自家窗口才丢，于是自家 popover（层级 25）能被识别（`SnipWindowInfo.swift:91-115`；`ScreenCaptureService.swift:78-96`）。
4. Dock 在 CGWindowList 里是一个 1512×982 的**整屏容器**，按点所在的最近一条边裁出 96pt 带子，避免「点 Dock 图标截出满屏」（`SnipWindowInfo.swift:117-161`）。
5. 标签文案区分「菜单栏 — SystemUIServer」与「应用名 — 标题」（`NetworkMonitorUI/SnipWindowLabel.swift:22-49`），并有断言把 UI 层数值与 Core 白名单钉在一起。
6. 回归测试 `SnipWindowLayerTests.swift`（白名单 4 层 + 非白名单 5 层 + 尺寸门槛 + Dock 贴边带 + 自家 popover 保留）。

**官方对应**：
- `专业版.md` 免费版即提供 `窗口检测`；专业版提供 `检测界面父/子元素`。
- 官方文档里 **Dock / 菜单栏 / 状态栏项** 只作为「界面元素检测」的粒度被间接提及（父/子元素），**没有把它们列成独立的「层级白名单」**。

**结论：超出官方文档的描述**（官方免费版只讲「窗口」，元素级要专业版；我们把系统层级当窗口纳入检测，并解决了 Dock 整屏容器的误框）。**仍不如**：没有 AX 元素粒度（SNIP-F14），「点某个状态栏图标」仍只能拿到层级 25 的那条容器窗口，而不是那一个图标。

**复核方式**：`git show 60c3a34`（"截图窗口识别到菜单栏/程序坞/状态栏层级，并放开自家面板窗口"）。

### 8.6 五条自证汇总

| 我们的修复 | 官方对应条目 | 结论 | 关键证据 |
|---|---|---|---|
| 坐标偏移（点数当像素） | v2.8 多屏截图 / v2.7.1 扩展屏错位 / SNIP-F19 px·dip 单位 | **对齐**（单位切换仍不如官方） | `SelectionGeometry.swift:51-73`；`SnipGeometryTests.swift`（20 断言） |
| 闪屏（首帧空白） | 官方文档无此条目；相关：`基础操作` 前台切换即取消 | **超出官方** | `SnipController.swift:147-171`；`SnipOverlayWindow.swift:69-103` |
| 工具条二级面板 | 官方专业版「自定义调色板颜色数量/拖动排序」 | **本地更优（官方无对应设计）**，一级可点性不如官方（ANN-F27） | `SnipTool.swift:30-37`；`SnipToolBarLayoutTests.swift`（49 断言） |
| 快捷键持久化 | 专业版「任意功能绑快捷键」+ `allow_simple_hotkeys` | **对齐**（任意绑定与忽略列表不如） | `SnipHotKeyComboResolver.swift:38-77`；`SnipHotKeyPreferencesTests.swift`（24 断言） |
| 菜单栏/Dock/状态栏层级 | 免费窗口检测 + 专业版父·子元素 | **超出文档描述**（AX 粒度仍不如） | `SnipWindowInfo.swift:9-36,117-161`；`SnipWindowLayerTests.swift` |

---

## 9. 未验证与已知局限（如实列出）

| 项 | 为什么未验证 | 建议怎么验 |
|---|---|---|
| 浏览器「复制图像」写进 NSPasteboard 的具体类型 | 代码路径只证明会走 `.png`/`.tiff`（`SnipController+Pin.swift:80`），没在真实 Chrome/Safari 里抓过 pasteboard 类型 | 在 Chrome 右键「复制图像」后打印 `NSPasteboard.general.types` |
| 贴图窗「透明区域不可点」与官方「伪透明」的可点差异 | 只能从 `isOpaque=false` + `backgroundColor=.clear` 推断（`PinWindow.swift:39-41`），未做点击穿透实验 | 贴一张带透明通道的 PNG，点透明区看能否拖动窗口 |
| `[General] gpu_acceleration` 对我们马赛克/模糊有无实际影响 | Core Graphics 是否走 GPU 取决于系统，代码里没有显式开关（`SnipMosaicProcessor.swift`） | Instruments GPU 计数器对比开/关 |
| 主题色是否「跟随系统」 | 截图工具条写死深色（`SnipToolBarView.swift:158`），算不算「跟随系统」取决于口径；SYS-F11 因此写「未验证」而非「缺失」 | 切换系统浅/深色后抓覆盖层快照 |
| Mac 版 Snipaste 是否真的提供「超级截屏 / 触发角 / OCR」 | `常见问题.md` 明确写「Mac 版 / Linux 版 / 滚动截图 / GIF 录制……请关注 这里」，即 Mac 版并非全量；文档没有逐项标注平台 | 装一份 Mac 版 Snipaste 2 实测 |
| 设置页三项「默认颜色 / 线宽 / 贴图不透明度」是否真的生效 | 附录 A 的 g25–g27 显示三个偏好键**全仓无消费方**；代码层面可判定「未生效」，但没有实机跑一次截图验证 | 改默认色 → 截一张 → 看新图元颜色 |
| 「可被恢复的已关闭贴图数」官方默认 1 的准确口径 | `基础操作.md` 写「默认设置/建议是 1」，但没标版本；本项目取 3（`PinWindowController.swift:11`） | 以实机 Snipaste 为准 |

---

## 10. 与旧调研文档的关系（避免误引）

旧的 `Snipaste-功能调研与实现评估.md` 给的是「完整重做一遍 Snipaste」的分档工期（A / A− / B / C 四档，区间到 135–155 人日）。本报告：

1. **没有采用其中任何数字**（包括 105.5 人日那套）；
2. 口径不同：本报告按「**逐项增量补齐**」估（P0 12 条 ≈13.5 人日、P1 12 条 ≈22 人日、P2 12 条 ≈27 人日），旧文档按「从零重做整机」分档；
3. 结论也不同：旧文档把「界面元素检测」列为 C 档高成本项（6 人日），本报告同样放 P2 并给 6 人日，但**理由写清了**（AX 权限与跨 App 稳定性），而不是照抄；
4. 旧文档说的「约 8–10 人日可复用基建」在本报告里体现为：Carbon 热键注册表、设置页、TestRunner 已经**存在**（`HotKeyRegistry.swift` 109 行、`SettingsCapturePane.swift` 279 行、20+ 个 Snip 测试文件），因此 P0 里没有「先搭脚手架」这类条目。

---

## 附录 A：本轮实际跑过的核查命令（可复跑）

> 每个「缺失」的行都能在本表找到对应命令与其命中数。路径一律 `NetworkMonitor/Sources`，`include=*.swift`。

### A.1 知识图谱（符号定位，优先）

```bash
~/.local/bin/codebase-memory-mcp cli search_graph \
  --project Users-bsfeng-IdeaProjects-toolbar-NetworkMonitor --query SnipOverlayView
# → total: 67 / search_mode: bm25 / results: 50
# 例：SnipOverlayView.swift 299-354 perform、:140-149 mouseMoved、:168-205 mouseDown …
```

### A.2 功能有无的 grep（每条附命中数与判定）

| 编号 | grep 模式 | 命中 | 判定 |
|---|---|---|---|
| g01 | `F5\|refreshSnip\|刷新截图` | 7 | 全部无关（`GlobalHotKey.swift:85` 只是显示名；其余为色值 0xF5xxxx）→ 刷新截图缺失 |
| g02 | `VNRecognize\|Vision\|OCR\|ocr` | 0 | → OCR 缺失 |
| g03 | `NSPrint\|printOperation\|发送到打印机` | 0 | → 打印缺失 |
| g04 | `ignoresMouseEvents = true\|setClickThrough\|mouseThrough` | 1 | 唯一命中是轻提示条 `SnipFailureNotice.swift:37` → 贴图鼠标穿透缺失 |
| g05 | `PinGroup\|pinGroup\|贴图组\|groupManager` | 0 | → 贴图组缺失 |
| g06 | `soloMode\|solo` | 1 | 命中 `BillingVisualLogicTests.swift:59`（无关词）→ Solo 缺失 |
| g07 | `grayscale\|invertImage\|反色\|灰度` | 2 | 均为菜单面板悬停气泡注释 → 灰度/反色缺失 |
| g08 | `EWResizableWindow\|resizeHandle\|liveResize\|边缘拖拽` | 0 | → 贴图边条缩放缺失 |
| g09 | `draggingEntered\|registerForDraggedTypes\|performDragOperation` | 3 | 全在 `Transfer/TransferPaneView.swift:69,232,247` → 贴图拖拽缺失 |
| g10 | `hotCorner\|触角\|triggerCorner` | 0 | → 触发角缺失 |
| g11 | `AXUIElement\|AXUIElementCopy` | 0 | → 界面元素检测缺失 |
| g12 | `parent\|子元素\|elementDetect` | 3 | `HarnessTokenModels.swift:164-165`、`MenuTabBarView.swift:90`，与截图无关 → 父/子元素切换缺失 |
| g13 | `---full\|---last\|---delay\|--area` | 0 | → 命令行选项缺失 |
| g14 | `透明.*白板\|transparentWhiteboard` | 0 | → 透明白板缺失 |
| g15 | `roundedSnip\|圆角截图` | 0 | → 圆角矩形截图缺失 |
| g16 | `笔尖\|penTips\|tipCount` | 0 | → 多笔尖缺失 |
| g17 | `didResignActive\|willResignActive\|applicationDidResignActive` | 0 | → 「别的程序激活即取消截图」缺失 |
| g18 | `ignoreList\|ignoredApps\|忽略程序` | 3 | 全在 `Clipboard/ClipboardPreferences.swift:61,149-150` → 截图热键忽略列表缺失 |
| g19 | `CommandLine.arguments\|ProcessInfo.processInfo.arguments` | 5 | `Debug/PanelOpenProbe.swift:39`、`Scripts/*`、`TestRunner/main.swift:9,15` → 产品无 CLI |
| g20 | `记号笔\|marker\|highlighter` | 2 | 剪贴板 `markerType`（`ClipboardPaster.swift:40,96`）→ 记号笔缺失 |
| g21 | `序号\|numbering\|badgeNumber` | 13 | 均为剪贴板/Token 序号注释 → 序号标注缺失 |
| g22 | `笔尖\|penTips\|tipCount`（在两个 scope 各跑一次） | 0 / 0 | → 确认不是 scope 漏检 |
| g23 | `pinColor`（`grep -rn` 全仓） | 1 | 只有定义 `PinWindowController.swift:74`，无调用方 → 色卡生产路径不走它 |
| g24 | `closeAll()` | 1 | 只有定义 `PinWindowController.swift:156`，无调用方 → 「退出时销毁已关闭贴图」缺失 |
| g25 | `annotationColor` | 3 | 只在设置页与键名定义，**无消费方** → 「默认颜色对新截图生效」实际未生效（见 §9） |
| g26 | `annotationLineWidth` | 3 | 同上，**无消费方** → 默认线宽未生效 |
| g27 | `pinDefaultAlpha` | 3 | 同上，**无消费方** → 贴图默认不透明度未生效 |
| g28 | `restoreLastClosed` | 1 | 只有定义 `PinWindowController.swift:123`，无调用方 → 恢复走的是 `restoreMatching`（`:39,52`） |
| g29 | `SnipAspectLock` | 7 | 定义 + 1 生产调用（`SnipSelectionState.swift:88`）+ 5 测试 → 仅 Shift 锁比例 |
| g30 | `dashed` | 24 | Sources 里落在 Snip 的只有模型 `SnipAnnotation.swift:39-49` 与渲染 `SnipAnnotationRenderer.swift:25-27`，**无 UI 入口** → 虚线「能力在、入口无」 |
| g31 | `contains(.space)\|空格键\|spaceKey` | 0 | 空格走 `KeyCode.space`（`SnipKeyCommand.swift:98`），非字符串匹配；此项以读码为准 |

### A.3 读码确认（凡「部分实现」都读过）

截图链路：`SnipController.swift`(274) / `SnipController+HotKeys.swift`(271) / `SnipController+Overlay.swift`(103) / `SnipController+Export.swift`(100) / `SnipController+Keyboard.swift`(243) / `SnipController+Pin.swift`(134) / `SnipOverlayView.swift`(352) / `SnipOverlayView+Actions.swift`(286) / `SnipOverlayView+Annotation.swift`(331) / `SnipOverlayView+Drawing.swift`(139) / `SnipOverlayWindow.swift`(138) / `SnipToolBarView.swift`(264) / `SnipToolPanelView.swift`(136) / `ScreenCaptureService.swift`(215) / `HotKeyRegistry.swift`(109) / `SnipPermissionGuide.swift`(32) / `SnipFailureNotice.swift`(77) / `SnipFileWriter.swift`(27)。
贴图链路：`PinWindow.swift`(184) / `PinWindowController.swift`(240) / `SnipClipboardRenderer.swift`(148)。
设置：`SettingsCapturePane.swift`(279) / `SnipPreferenceKey.swift`(16) / `AppCoordinator+Snip.swift`(37)。
Core：`SnipAnnotation.swift`(154) / `SnipTool.swift`(54) / `SnipAnnotationRenderer.swift`(181) / `SnipAnnotationCompositor.swift`(66) / `SnipSelectionState.swift`(202) / `SnipWindowInfo.swift`(163) / `SnipPixelSampler.swift`(91) / `SnipClipboardClassifier.swift`(77) / `SelectionGeometry.swift`(74) / `SnipSizeInput.swift`(73) / `SnipSelectionHistoryCoding.swift`(33) / `SnipSaveDirectory.swift`(40) / `SnipFileNaming.swift`(29) / `SnipHotKeyComboResolver.swift`(95)。
UI：`SnipKeyCommand.swift`(137) / `SnipWindowLabel.swift`(50) / `SnipToolBarLayout.swift`(179)。

### A.4 官方文档抓取（可复跑）

```bash
mkdir -p /tmp/snip && cd /tmp/snip
for n in 内置快捷键 基础操作 高级技巧 高级设置 命令行选项 专业版 常见问题 更新日志; do
  curl -sL --compressed --max-time 30 -o "$n.md" -w "%{http_code} %{size_download} $n\n" \
    "https://docs.snipaste.com/wiki/$n.md"
done
wc -c *.md   # 123367 total
```

版本归属的复核（`更新日志.md` 里每条功能前一行就是版本号）：

```bash
awk '{if(/^## v/){v=$2} /刷新截图|超级截屏|圆角|OCR|条形码|触发角|多选|裁剪|灰度|反色|背景模式|二次编辑|序号|放大镜标注|虚线|调色板|笔尖|颜色卡片|分组/{print v": "$0}}' 更新日志.md
```

### A.5 文档索引未更新的说明（刻意）

本报告**没有改 `docs/索引.md`**：任务约束是「只写 docs/调研/Snipaste-官方文档逐项对照.md 一个文件、不改任何其它仓库文件」。按项目 `文档规范`「新增文档必须同步更新 docs/索引.md」，这一处需要由 lead 在合并时补一行（建议文案如下）：

```
→ [Snipaste 官方文档逐项对照](调研/Snipaste-官方文档逐项对照.md) — 八份官方 wiki 逐条对照现状，P0 12 条 ≈13.5 人日
```

（本条写在文末而不是补进索引，是因为索引不属于本任务的写入范围；执行时已 add 过、随后已 `git checkout` 还原，`git status` 只有本文件一个新增。）
