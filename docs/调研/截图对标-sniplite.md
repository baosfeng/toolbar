# 截图功能对标 sniplite 调研结论

> 目的：把开源截图贴图工具 **sniplite**（https://github.com/MrTangLuyao/sniplite ）的功能全集与我们当前的截图/贴图实现逐条对照，给出补差优先级；只记录核实过的结论。
> sniplite 基线：main 分支快照（v1.1.2，x86-64 汇编 + C，仅 Windows 10/11），本地副本 `/tmp/sniplite-src/sniplite-main`，索引名 `private-tmp-sniplite-src-sniplite-main`。
> 本项目基线：`NetworkMonitor/Sources/NetworkMonitor/Snip/`（29 个文件，4277 行）、`Pin/`（4 个文件）、`Settings/SettingsCapturePane*.swift`、`NetworkMonitorCore/Infrastructure/Snip/`（25 个文件）。
> 口径提醒：sniplite 是 Windows 工具，靠 Win32 + DXGI 实现，**对标的是能力，不是代码可移植性**。

## 0. 一句话结论

**最该补的 3 项：① OCR 文字识别（选区→文字→复制/贴图，双方都空白）② 滚动长截图（双方都空白，唯一需要自研大工程）③ 标注工具补完整度（序号工具 + 已绘标注拖动/缩放/改样式）。**

排序理由：OCR 与长截图在我们和 sniplite 都没有，是纯增量赛道（用户明确点名）；标注完整度是**唯一 sniplite 明确比我们强**的成熟能力维度（它有 picking / 8 手柄缩放 / restyling / 序号，我们只能选中+删除+文字旋转）。

## 1. sniplite 功能全集（按实际读到的代码，不按宣传）

### 1.1 截图

- 覆盖层一个窗口盖住整个虚拟屏（多屏天然连续），无缝跨屏选区 —— `src/ov_layout.inc:69-78`（Shot 是虚空屏矩形 + 最多 16 个 monitor tile）
- 捕获后端二选一：**极速 DXGI 桌面复制** / **省内存 GDI**，用户可在首选项切换 —— `src/shot.h:1-4, 56-62`；首选项文案与内存口径 `res/sniplite.rc:45-48`
- 捕获用 GPU 纹理 + 用透明窗口「poke」逼 DWM 出一帧，避开「拍到自己」—— `src/shot.h:31-43`
- 首帧计时埋点（hotkey→可见 / grab / windows / paint / focus）—— `src/overlay.h:5-12`
- 窗口/控件检测：枚举最多 1024 个窗口 —— `src/ov_layout.inc:13`
- **同一位置嵌套窗口链**（最多 16 层），选区阶段滚轮上下换层级（「选大一点/小一点」）—— `src/ov_layout.inc:14, 156, 158`；切换实现 `src/ov_input.S:693-709`；入链 `src/ov_base.S:895-933`
- 放大镜 25×19 像素网格 + 坐标 + 色值，Shift 切 RGB/HEX —— `src/ov_layout.inc:8-9, 113-115, 199`；Shift 切换 `src/ov_input.S:1060-1066`
- 取色：选区阶段按 **C** 复制光标下颜色值 —— `src/ov_input.S:1010-1020`（`copy_color`）
- 全屏（Ctrl+A 选中光标所在显示器）—— `src/ov_input.S:1075-1089`
- 方向键 1 像素挪选区 —— `src/settings.c:411`
- **无延时截图**（全库无 delay/倒计时实现，`delay` 仅 `overlay.h:11` 注释命中）

### 1.2 标注（9 个工具 + 二次编辑）

- 工具集固定 9 个：矩形 / 椭圆 / 直线 / 箭头 / 画笔 / 荧光笔(marker) / 马赛克 / 文字 / 序号 —— `src/ov_layout.inc:19-28`；工具条图标同集 `src/draw.h:45-48`
- 撤消 / 重做 / 贴图 / 保存 / 关闭 / OK 六个动作按钮 —— `src/ov_layout.inc:45-50`
- **二次编辑**：命中拾取、重设样式（换色/换线宽）、方向键微调、拖拽移动（DR_AMOVE）、抓手缩放（DR_AGRAB）、8 个手柄缩放（EDGE_L/T/R/B + END_A/END_B）—— `src/ov_edit.S:1-19`（文件头声明的能力集）+ `src/ov_layout.inc:29-44, 53`
- 文字：系统插入法（IME 组字/候选窗定位）—— `src/ov_edit.S:23-36`（COMPOSITIONFORM/CANDIDATEFORM）；打字态 **Ctrl+V 粘贴**、Esc 结束 —— `src/ov_input.S:944-956`；单条文本上限 20000 字符 `src/ov_layout.inc:15`
- 序号工具：编号文案内联格式化为 `%d` —— `src/ov_base.S:10-11`
- 马赛克是块平均像素化，**没有高斯模糊** —— `src/draw.h:39-40`；全库 `模糊|高斯|gauss|blur` 0 命中
- 无橡皮擦：靠拾取 + Del 删除 —— `src/settings.c:404` 之外无擦除路径

### 1.3 输出

- 复制（Enter 或双击）/ 保存（Ctrl+S）/ 贴图（Ctrl+T）/ 撤消 Ctrl+Z / 退出 Esc —— `src/settings.c:398-406`
- 保存对话框格式：**PNG / JPEG / BMP** 三种 —— `src/image.S:189-202`（过滤器字符串与 `w_jpg/w_jpeg/w_bmp` 扩展名 `src/image.S:150-157`）
- 默认文件名模板 `sniplite_%04d-%02d-%02d_%02d-%02d-%02d.png`、记住上次目录 —— `src/image.S:162-167, 209`
- 保存对话框跑在独立短命进程里（不让 shell DLL 常驻后台）—— `src/image.h:19-22`
- 无云上传 / 分享 / 图床（`上传|图床|Imgur|分享` 全库仅 README 1 命中）

### 1.4 贴图

- 无边框置顶窗口：拖动移动、滚轮缩放、**Ctrl+滚轮透明度**、双击或 Esc 关闭、右键菜单、可拖边框缩放、最小化/最大化/还原 —— `src/pin.S:1-5`、`src/pin.S:53-56`
- 贴图来源：截图、剪贴板图片、**剪贴板文字**（转成图片贴出）—— `src/image.h:5-14`
- 全部贴图 隐藏/显示（Shift+F3 默认）、贴图数量与存在性查询 —— `src/pin.h:8-11`、`src/config.c:14`

### 1.5 集成 / 其它

- 托盘图标 + 右键菜单；Explorer 重启后自动重建图标 —— `src/main.c:16, 44-46`
- 3 组全局热键可录制（截图 / 贴图 / 隐藏贴图），注册失败有红叉状态位 —— `src/config.h:5-12`、`src/settings.c:58-69`
- 开机自启（启动目录快捷方式）、配置文件 `sniplite.ini` 可打开/定位/恢复默认 —— `src/settings.c:81-123`、`res/sniplite.rc:26-39`
- **命令行**：`capture [--full] [--out] [--rect] [--clip] [--pin]` / `pin [图片]` / `settings` / `update [--install]` / `status` / `quit` / `--json` / `--hotkey` / `--gdi|--dxgi`，退出码 0-5 —— `src/cli.c:6-25, 173-213`
- 自动更新：启动后 1 分钟首查、之后每日，可关 —— `src/main.c:20-21`、`README.md` 「怎么更新」
- 单实例 + IPC（`sniplite` 无参启动＝看状态）—— `src/ipc.c`、`src/cli.c:193-209`
- 内置快捷键速查表（分组：截图 / 贴图 / 小技巧）—— `src/settings.c:397-413`

### 1.6 明确没有的能力（用于确认空白赛道）

| 能力 | 取证 |
|---|---|
| OCR / 文字识别 | `search_code --pattern 'Ocr|OCR|文字识别' --regex true` → **0 命中** |
| 滚动长截图 / 拼接 | `search_code --pattern 'scroll|滚动|长截|拼接'` → **0 命中** |
| 录屏 / GIF / 视频 | `search_code --pattern 'gif'` → 0；`'录屏|录制|拼图|截图拼接'` → 0 |
| 高斯模糊打码 | `'模糊|高斯|gauss|blur'` → 0（只有马赛克） |
| 测量 / 标尺 | `'测量|ruler'` → 0 |
| 云端上传 / 分享链接 | `'上传|图床|Imgur|分享'` → README 1 命中（无实现） |

## 2. 我们当前已实现（逐条带证据）

### 2.1 截图链路

- 29 个 Snip 文件（`ls Sources/NetworkMonitor/Snip/` + `wc -l`：合计 4277 行，最大 `SnipToolPanelView.swift` 307 行）
- 捕获三档回退：macOS 26+ `SCScreenshotConfiguration` / 15.2+ 按矩形 / 14.0+ `SCContentFilter`；像素尺寸取显示模式而非 `CGDisplayPixelsWide` —— `ScreenCaptureService.swift:8-9, 30-41`
- 每屏一个覆盖层（`overlays: [SnipOverlayWindow]`），**注释明确「M1 单屏、跨屏 M2」** —— `SnipController.swift:9-10, 37`
- 抓屏与抢前台顺序（先抓后抢）—— `SnipController.swift:147-170`
- 重入保护（`isStarting`）与覆盖层二次按热键重新聚焦 —— `SnipController.swift:128-142`、`SnipController+Keyboard.swift:165-170`
- 窗口检测（默认开，Tab 开关）：悬停高亮 + 单击选整窗、拖拽选任意区域 —— `SnipOverlayView+Mouse.swift:26-33, 62-73`；窗口白名单层级 0/20/24/25 —— `ScreenCaptureService.swift:59-71`
- 放大镜 120pt + 15 像素跨度 + 网格 + 中心像素框 + 坐标 + 色值 —— `SnipOverlayView+Drawing.swift:73-137`
- 取色：C 键把光标像素色写入剪贴板 —— `SnipKeyCommand.swift:130`、`SnipKeyCommand.swift:24-25`
- RGB/HEX 切换：Shift —— `SnipOverlayView.swift:251-256`
- 全屏 ⌘A、指针显隐 `、工具条显隐 空格、选区历史 `,` / `.`、上次选区 R —— `SnipKeyCommand.swift:106-137`
- **延时截图** ⌥⇧D（3 秒）—— `SnipController.swift:66-72, 118-126`
- 选区历史持久化（最近 N 次，逗号/句号循环）—— `SnipController.swift:87-105`
- 权限引导 + 失败轻提示（日志 + beep + 提示条）—— `SnipPermissionGuide.swift:13-31`、`SnipController+Keyboard.swift:172-192`（`failureDescription` / `fail`）

### 2.2 标注

- 10 个工具：矩形 / 椭圆 / 直线 / 折线 / 箭头 / 画笔 / 马赛克 / **模糊** / 文字 / **橡皮擦** —— `SnipTool.swift:6-16`
- 一级工具条 4 个常驻 + 二级面板收纳，均可自定义 —— `SnipTool.swift:30-38`、`SettingsCapturePane+ToolBar.swift`
- 渲染（含虚线、实心、箭头几何）—— `SnipAnnotationRenderer.swift:29-60`
- 文字：字号随滚轮缩放（`fontScale`）、⌘R 旋转 90° —— `SnipAnnotation.swift:109-113, 136-138`、`SnipOverlayView+Annotation.swift:249-257`
- 撤消 / 重做 / 移除全部（⌘⇧Z）—— `SnipKeyCommand.swift:151-155`、`SnipOverlayView+Editing.swift:47-52`
- 二次编辑能力**仅三件**：点中选中（同类型也算）、Del 删除、文字旋转 —— `SnipOverlayView+Editing.swift:83-133`、`SnipOverlayView+Annotation.swift:249-257`
- 橡皮擦按轨迹分段擦除 —— `SnipOverlayView+Annotation.swift:259-288`

### 2.3 输出

- 复制：`NSPasteboard.general.writeObjects([NSImage])`（未显式写 PNG 表示）—— `SnipController+Export.swift:10-23`
- 快速保存 ⌘⇧S / 另存 ⌘S：**只允许 PNG** —— `SnipController+Export.swift:49-61, 76-99`（`:85` `allowedContentTypes = [.png]`）；`SnipFileWriter.swift:15-26` 只有 `writePNG`
- 复制后自动保存（偏好开关）—— `SnipController.swift:210-218`
- 贴图 ⌘T / 中键 —— `SnipController.swift:240-250`、`SnipOverlayView+Mouse.swift:35-40`

### 2.4 贴图

- 置顶面板四件套（`.nonactivatingPanel` + `.screenSaver` + 四项 collectionBehavior + accessory 策略）—— `PinWindow.swift:7-10, 41-56`
- 键位：关闭 / 销毁 / 顺逆时针旋转 / 水平垂直镜像 / 缩略图 / 缩放 / 透明度 / 重置 / ⌘⇧C 复制来源纯文本 —— `PinWindow.swift:85-99`
- 滚轮缩放（0.1–10 倍）、Ctrl+滚轮透明度 —— `PinWindow.swift:103-117`
- 剪贴板内容源分类贴图：图片 / 图片文件（首贴图、再贴降级路径文本）/ 文本 / HTML / 文件 / 颜色 —— `SnipController+Pin.swift:8-49`
- 关闭可恢复池（1–10 张，偏好可调）+ 隐藏全部 + 屏幕变化回收 —— `PinWindowController.swift:10-16, 100-152`、`SettingsCapturePane+Pin.swift:26-40`
- 贴图保存也是 PNG-only —— `PinWindowController.swift:230-248`
- 贴图写入像素守卫（12000×12000 峰值 2764MB 的实测教训）—— `SnipController+Pin.swift:10-16`

### 2.5 设置 / 集成

- 「截图与贴图」页：标注默认色（7 色 hex）+ 线宽三档、贴图默认不透明度、复制后自动保存、快速保存目录、工具条自定义（位置/显隐/顺序/常驻工具/动作按钮）、6 个热键录制 —— `SettingsCapturePane.swift:70-195`、`SnipHotKeyPreferences.swift:11-46`
- 无命令行接口；无自动更新；无用户可选的「省内存」捕获模式（只有内部三档回退）

### 2.6 我们明确没有的能力（取证）

| 能力 | 取证 |
|---|---|
| OCR | `search_code --pattern 'OCR|VNRecognizeText|VisionKit' --regex true` → **0 命中** |
| 滚动长截图 | `'scrolling|长截图|scrollCapture|stitch'` → 只命中 `scrollWheel`/`handleStyleScroll`，无拼接 |
| 录屏 / GIF | `'AVAssetWriter|SCStream|录屏|GIF'` → 无 `AVAssetWriter`，仅捕获用 `SCContentFilter` |
| 云端上传 / 分享面板 | `'上传|图床|Imgur|shareSheet'` → 只有局域网互传 `TransferHTTPClient.upload`（`Transfer/Service/TransferHTTPClient.swift:83-104`），无对外分享 |
| 序号标注 | `SnipTool.swift:6-16` 10 个 case 无 number/序号 |
| 已绘标注移动/缩放/改色 | `SnipOverlayView+Editing.swift`、`SnipOverlayView+Annotation.swift` 内对选中项只有 select/delete/rotate |
| 嵌套窗口层级选择 | `SnipOverlayView+Mouse.swift:32` 单次 `SnipWindowHitTesting.window(at:in:)` 取一个，滚轮只调样式/字号（`SnipOverlayView+Mouse.swift:107-120`） |
| 跨屏选区 | `SnipController.swift:9-10` 自述 M1 单屏 |

## 3. 三栏对比

### 3.1 他们有、我们没有（按价值排序）

| # | 能力 | sniplite 证据 | 我们现状 |
|---|---|---|---|
| 1 | 嵌套窗口链（滚轮同点上下层换范围） | `src/ov_input.S:693-709`、`src/ov_base.S:895-933`、`src/settings.c:410` | 只取最顶层命中窗口：`SnipOverlayView+Mouse.swift:26-33` |
| 2 | 序号标注（自动递增编号） | `src/ov_layout.inc:27`、`src/ov_base.S:10-11` | 无该工具：`SnipTool.swift:6-16` |
| 3 | 已绘标注拖拽移动 / 8 手柄缩放 / 改样式 | `src/ov_edit.S:1-19`、`src/ov_layout.inc:29-44` | 只能选中 + 删 + 文字旋转：`SnipOverlayView+Editing.swift:83-133` |
| 4 | 保存多格式（PNG/JPEG/BMP） | `src/image.S:150-157, 189-202` | PNG-only：`SnipFileWriter.swift:15-26`、`SnipController+Export.swift:85` |
| 5 | 荧光笔（marker，半透明刷） | `src/ov_layout.inc:24`、`src/draw.h:46` | 无 marker（只有画笔/模糊）：`SnipTool.swift:6-16` |
| 6 | 用户可选「省内存」捕获模式 | `res/sniplite.rc:45-48`、`src/shot.h:56-62` | 三档内建回退，无用户开关：`ScreenCaptureService.swift:8-9` |
| 7 | 命令行接口（capture --rect/--full/--clip/--pin、--json、退出码） | `src/cli.c:6-25` | 无 |
| 8 | 自动更新（首查 1 分钟 + 每日） | `src/main.c:20-21` | 无 |
| 9 | 捕获首帧计时埋点 | `src/overlay.h:5-12` | 只有日志，无分段落点 |
| 10 | 跨屏连续选区（单窗口覆盖虚拟屏） | `src/ov_layout.inc:69-78` | M1 单屏：`SnipController.swift:9-10` |

### 3.2 双方都有（差异说明）

| 能力 | sniplite | 我们 | 差异 |
|---|---|---|---|
| 框选 + 拖拽调整（8 手柄） | `src/ov_layout.inc:36-41` | `SnipSelection.swift` + `SnipOverlayView+Mouse.swift:62-73` | 持平：都支持手柄调整与 Shift 锁比例 |
| 窗口检测 | 1024 窗口枚举 + 链式层级 | 白名单层级 0/20/24/25 + hover 高亮 | 我们含菜单栏/状态栏项，sniplite 含嵌套链 |
| 放大镜 + 坐标 + 色值 | 25×19 网格，Shift 切 RGB/HEX | 120pt/15px 网格，Shift 切 RGB/HEX | 持平 |
| 取色并复制 | C 键 `copy_color` | C 键 `.copyColor` | 持平 |
| 全屏/整屏选区 | Ctrl+A（光标所在屏） | ⌘A（当前覆盖层 = 当前屏） | 持平 |
| 撤销/重做 | Ctrl+Z / Ctrl+Y | ⌘Z / ⌘Y（⌘⇧Z 改为清空，与官方口径一致） | 持平 |
| 标注 9 项基础工具 | 9（含序号、荧光笔） | 10（含模糊、橡皮擦） | 各有偏科 |
| 文字标注（IME、粘贴） | 系统插入法 + Ctrl+V | 原生 `NSTextView` 输入（IME 天然可用） | 持平，粘贴能力待确认 |
| 贴图（置顶/拖动/缩放/透明度/隐藏全部/双击关） | `src/pin.S:1-5` | `PinWindow.swift:85-117`、`PinWindowController.swift:100-110` | **我们更强**（旋转镜像/缩略图/恢复池/来源文本/滚轮更细档） |
| 从剪贴板贴图 | 支持图片与文字 | 图片/文件/文本/HTML/颜色五类 + 降级策略 | **我们更强** |
| 热键可录制 | 3 组 | 6 组（截图/贴图/延时/隐藏贴图/设置/白板） | **我们更多** |
| 托盘/菜单栏 | 托盘图标 + 菜单 | 菜单栏 App + 面板 | 持平 |
| 设置页 | 5 页（常规/截屏/控制/更新/关于） | 「截图与贴图」1 页 + 工具条自定义 | 我们少了「更新页」 |
| 保存目录可定制/记住 | 记住上次目录 | 快速保存目录偏好 + 打开按钮 | 持平 |
| 性能取向 | 汇编 + DXGI，用户可选省内存模式 | ScreenCaptureKit 三档回退 | sniplite 快，我们胜在无额外显存占用 |

### 3.3 我们有、他们没有

| 能力 | 我们证据 | 价值 |
|---|---|---|
| 延时截图（3 秒） | `SnipController.swift:66-72, 118-126` | 中：截菜单/悬停态必需 |
| 选区历史（逗号/句号循环 + R 复用） | `SnipController.swift:87-105`、`SnipKeyCommand.swift:111-112, 131` | 中高：重复截同一区域高频 |
| 高斯模糊打码 | `SnipTool.swift:14`、`SnipAnnotationRenderer.swift:50-52` | 高：比马赛克更常用于打码隐私 |
| 橡皮擦（轨迹分段擦除） | `SnipOverlayView+Annotation.swift:259-288` | 中 |
| 多屏各自覆盖层 + 指针显隐 | `SnipController.swift:37, 183-203` | 中 |
| 工具条自定义（位置/显隐/顺序/常驻工具/标签三档） | `SettingsCapturePane+ToolBar.swift`、`SnipToolBarConfigurationResolver.swift` | 高：sniplite 工具条是硬编码 |
| 贴图关闭可恢复池 | `PinWindowController.swift:114-135` | 中高 |
| ⌘⇧C 复制贴图来源纯文本 | `PinWindow.swift:20-27`（字段）+ `PinWindow.swift:85-99`（命令） | 中 |
| 贴图旋转/镜像/缩略图 | `PinWindow.swift:85-99` | 中 |
| 复制后自动保存 | `SnipController.swift:210-218` | 中 |
| 剪贴板内容源分类贴图（含颜色卡） | `SnipController+Pin.swift:8-49`、`PinWindowController.swift:84-96` | 高 |
| 失败轻提示 + 权限引导 | `SnipFailureNotice.swift`、`SnipPermissionGuide.swift:13-31` | 中 |

## 4. 补差清单 Top 8

| 优先级 | 功能 | 用户价值 | 成本 | 涉及我们的文件 | 风险 |
|---|---|---|---|---|---|
| P0 | **OCR 文字识别**：选区/贴图 → 识别 → 复制文本 / 贴着看 | 高：截图 90% 目的是把图里的字拿出来；双方都空白，直接差异化 | 中 | 新增 `NetworkMonitorCore/Infrastructure/Snip/SnipTextRecognizer.swift`（Vision `VNRecognizeTextRequest`，.accurate + zh-Hans/en）；接线 `SnipController+Export.swift`、`SnipKeyCommand.swift`（新增 `copyText`/`recognize`）、`PinWindow.swift`（贴图上识别）；测试进 `TestRunner` | 中英混排/竖排精度；首次加载语言模型延迟（需预热）；结果落剪贴板要明确"纯文本"语义，避免与 ⌘C 图片冲突 |
| P0 | **滚动长截图**：选区内自动滚动 N 屏 → 重叠匹配拼接 | 高：聊天记录/长表单/文档是刚需；双方都空白 | 大 | 新增 `SnipScrollingCapture*.swift`（CGEvent 滚轮合成 + 两次捕获差分定位 + 接缝融合）；接口挂 `SnipCaptureService`；UI 挂快照工具条二级面板 | 高：滚动惯性/固定表头/懒加载会破坏匹配；需可中断与预览确认；对 App 权限（输入监控）有要求 |
| P1 | **序号标注**（自动递增 1,2,3…） | 中高：做步骤说明/教程图的第一需求 | 小 | `SnipTool.swift` 加 `case number`、`SnipAnnotationKind` 加 `number`、`SnipAnnotationRenderer` 画圆底数字、`SnipToolBarConfigurationResolver`/`SnipPanelLabelText` 补标签、`SnipAnnotationComposer` 烧图 | 编号续号规则（删中间项是否重排）要先定口径 |
| P1 | **已绘标注二次编辑**：拖动移动 + 8 手柄缩放 + 改色/线宽 | 中高：sniplite 的成熟能力，我们只能删了重画 | 中 | `SnipOverlayView+Editing.swift`（新增 `beginMove/scaleSelected`）、`SnipAnnotationStack.swift`（已有 `replace`）、`SnipAnnotationConstraint.swift`、工具条样式变更要回灌选中项 | 中：命中判据（`isStroke` 已让轨迹类让给绘制）与选区/工具条抢占鼠标要理清 |
| P1 | **输出多格式**：保存 JPEG/PNG（+ 粘贴板写 PNG 与 TIFF 双表示） | 中：JPEG 是发群/邮件默认需求，PNG-only 常被抱怨体积大 | 小 | `SnipFileWriter.swift`（`writePNG` → `write(image:format:)`）、`SnipController+Export.swift:85`、`PinWindowController.swift:234`、`SnipFileNaming.swift` | 低：质量参数与色彩配置（sRGB）要固定口径 |
| P2 | **嵌套窗口层级选择**（同点滚轮上下层） | 中：截「某个按钮」时经常要先截到父窗口再裁 | 小-中 | `SnipWindowInfo.swift`（`SnipWindowHitTesting` 增链构建）、`SnipOverlayView+Mouse.swift:107-120`（滚轮让位给层级切换）、`SnipOverlayView.swift` 状态加 level | 中：滚轮当前已被"调粗细/改字号"占用，需按相位分流（选区相位才切层级，这点 sniplite 也是这么分的） |
| P2 | **性能：用户可选「省内存/极速」捕获模式 + 首帧分段计时** | 中：给低配机与多屏 5K 一个出口；也让性能问题可量化 | 小-中 | `SnipPreferenceKey.swift`、`SettingsCapturePane.swift`（新增一行）、`ScreenCaptureService.swift:44-48`（按偏好裁剪捕获路径）、新增 `SnipCaptureTiming.swift`（hotkey→抓屏→上屏三段） | 低：模式切换不能让用户以为"选了省内存就截不到"；计时埋点只在 DEBUG/日志层 |
| P2 | **分享/上传**（把截图一键发到本机互传会话或自建图床） | 中：团队内传递截图的高频动作；双方都空白 | 中 | 复用 `NetworkMonitorCore/Transfer/Service/TransferHTTPClient.swift:83-104` 与 `TransferService+Send.swift`；入口 `SnipController+Export.swift` + 工具条动作按钮（`SnipBarAction`） | 中：URL 时效/隐私（图留在局域网 vs 公网）、失败态要有明确提示，不做静默失败 |

## 5. 未决 / 待后续确认

1. sniplite 的「荧光笔」与我们「画笔 + 半透明色」是否等价——需看 `src/draw.S` 的 marker 混合模式后再定；当前只按工具枚举记为差异项。
2. 我们 `NSPasteboard.writeObjects([NSImage])` 实际写入哪些 UTI（TIFF？PNG？）未实测；如要抄 sniplite 的"多格式回写"，先用 `pbpaste -Prefer png` 之类方式验证。
3. 跨屏选区（sniplite 天然支持，我们 M1 单屏）不在 Top 8 内，但它是「长截图/宽图」之外的体验缺口，建议在长截图设计里一并处理。
