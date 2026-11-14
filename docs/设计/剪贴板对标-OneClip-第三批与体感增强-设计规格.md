# 剪贴板对标 OneClip 第三批 + 全 App 体感增强 设计规格

> **何时阅读：** 改剪贴板文件条目摘要、缩略图失败重试、卡片悬停/首启引导/快捷键帮助、设置页存储管理，或新增动效 / 声效 / 触觉 / 材质能力前。
> 状态：已实现并验收（分支 clipboard-parity-3：四道门禁全绿 + 快照结构自证；两条实现期偏差已补齐）｜基线：main @ 674a1ec｜日期：2026-11-13，验收 2026-11-14
> 相关：[第一批增量设计规格](剪贴板对标-OneClip-增量设计规格.md) · [第二批增量设计规格](剪贴板对标-OneClip-第二批增量设计规格.md) · [OneClip 调研结论](../调研/剪贴板对标-OneClip-调研结论.md)
> 约束：单文件 ≤500 行 / 15 KiB（15360 字节）；注释必须中文；日志统一走 `LoggingService`

## 1. 背景

前两批已合并发版。本批分两条线：

- **A 线 · 剪贴板功能对齐**：OneClip 侧经调用点核查仍为「真实存在且我方缺失」的项（取证报告 `/tmp/toolbar-audit-oneclip.md` 表 2）。
- **B 线 · 体感增强**：用户明确要求对**动效 / 声效 / 材质 / 渲染**做系统增强。取证基线：全 App 只有 Transfer 一处成套动效（`TransferMotion.swift`），剪贴板面板零声效、零悬停、卡片选中零过渡，`NSVisualEffectView` 全仓仅剪贴板面板与 Debug 快照两处，`NSShadow` / `CAShapeLayer` / `CATransition` / `NSHapticFeedbackManager` 全仓 0。

## 2. A 线 · 剪贴板功能增量（4 项）

### A1 文件条目按分类聚合摘要（P0，Core 纯函数 + 采集接线）

**问题**：`PasteboardWatcher` 把多文件路径 `joined(separator: "\n")` 直接当正文，`ClipboardPreview.make` 又把换行折叠成空格 ⇒ 卡片正文是一长串绝对路径，认不出「这是什么文件」。

**设计**：
1. Core 新增纯函数 `ClipboardFileSummary`（不 import AppKit）：
   - `summarize(paths: [String]) -> String`
   - 单个文件 → `"<族名>: <文件名>"`，如 `"文档: 季度报告.pdf"`
   - 多个文件 → `"文件 (N个): <族名>: <文件名1>; <族名>: <文件名2>; …"`
   - 分族复用既有 `ClipboardFileClassifier` 的族名，**不新增第二套分类**；同族多个文件合并写成 `"文档 ×2: a.docx、b.docx"`。
   - 尾部超长时按 `ClipboardLimit.previewMaxLength` 截断并补省略号；截断不得把某个文件名切成半个（按条目边界截断）。
   - 空数组返回空串；无法识别族名落既有 `other` 族名。
2. 接线点只有一个：`PasteboardWatcher` 文件分支生成 `preview` 时改用 `summarize`，**`text` 列保持原路径列表不变**（复制回剪贴板必须还原原始路径，不能丢语义）。
3. 数据库 schema 不变；历史条目不回填。

### A2 缩略图解码多级兜底 + 失败可重试（P1）

**问题**：`ClipboardThumbnailLoader` 只有一条 ImageIO 路径，失败即 `markFailed` 且注释「本会话内不再重试」⇒ 一个坏文件让该哈希整个会话停在占位符。

**设计**：
1. Core 新增纯状态机 `ClipboardThumbnailRetryPolicy`（无 AppKit）：
   - `shouldRetry(hash:now:) -> Bool`：同一哈希失败后冷却 `cooldown`（默认 30s）内不再尝试；冷却结束允许重试；累计失败达 `maxAttempts`（默认 3）后转为终态不再重试。
   - `markSucceeded(hash:)` 清空该哈希全部失败记录。
   - `reset()`。
2. App 层解码加一级兜底：ImageIO `CGImageSource` 主路径失败后，回退 `NSBitmapImageRep(data:)` → `CGImage`，再走既有降采样出口；两路都失败才记失败。
3. 失败记忆改由 `ClipboardThumbnailRetryPolicy` 判定，面板重开 / 重绘时按策略决定是否重新请求。

### A3 卡片悬停态与全文展开（P1，面板 UI）

**问题**：卡片正文固定 7 行截断，`NetworkMonitor/Clipboard/` 全目录 `mouseEntered` / `trackingArea` 0 命中，鼠标滑过毫无反应。

**设计**：
1. 卡片新增 hover 态：描边加粗 + 底色微提亮（不改尺寸、不改布局、不缩放）。
2. 悬停 `0.45s` 后在卡片**下方**（空间不足则上方）弹出全文浮层：`.hudWindow` 材质、圆角 12、宽 `280pt`、最大 `9` 行、超长内部滚动，显示完整正文 + 类型 / 来源 / 时间 / 复制次数。
3. 浮层不抢焦点、不拦截鼠标（`ignoresMouseEvents = true`），移出卡片或面板收起即消失。
4. 全文仍是纯文本渲染，不做富文本；图片 / 文件条目浮层显示既有摘要与元信息。
5. 无障碍：浮层内容设置 `setAccessibilityLabel`。

### A4 首次引导与快捷键帮助（P2，面板 UI + 偏好接线）

1. 首次打开面板且历史为空时显示引导态（图标 + 两句话 + 三条快捷键胶囊），与「无匹配结果」空态区分；关闭后写 `ClipboardPreferences.hasGuidedClipboardAccess`（**该标记已存在但全库 0 调用点，本批必须接上**）。
2. 工具条新增「?」按钮（`setAccessibilityLabel("快捷键帮助")`），点击弹出 hudWindow 浮层列出全部键位（⌘1–9 / ↵ / ⌥↵ / ⌘S / ⌘⇧S / ⇧Tab / ⌘D / ⌘⌫ / ⌘⇧⌫ / Esc / ←→ / ⌘,）。点外部或 Esc 收起。

## 3. B 线 · 体感增强

### B1 统一动效基础设施 `MotionKit`（App 层新建）

- 现有 `TransferMotion` 是唯一成套实现，且自带「减弱动态效果」判断与通用曲线。本批新建 `MotionKit` 作为**全 App 共用**入口，`TransferMotion` 保持不动（避免跨模块回归），二者时长与曲线口径一致。
- 接口（全部 `@MainActor`）：
  - `isEnabled`：跟随 `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`；关闭时所有方法直接落终态。
  - `durations`：状态 0.12s、展开 0.34s、弹层 0.22s、关闭 0.15s、错峰 0.024s（与 `TransferMotion` 同口径）。
  - `fadeIn(_:offsetY:delay:)` / `fadeOut(_:duration:completion:)` / `popIn(_:)` / `press(_:)` / `release(_:)` / `shake(_:)` / `crossFade(layer:duration:)` / `stagger(index:)`。
  - 单一实现，剪贴板 / 面板 / 设置都调它，**不允许各模块自己再写一份 CAAnimation**。

### B2 剪贴板面板动效接线

- 面板展开：材质底 `alphaValue` 0→1 + `transform.translation.y` 8→0（0.18s），收起反向；**必须判断减弱动态效果**。
- 卡片进场：首屏与前 12 张按 `stagger` 错峰淡入（每张 0.024s，总上限 0.3s）。
- 选中切换：卡片描边与底色走 0.12s 交叉过渡（`crossFade`），不再硬切 `needsDisplay`。
- 收藏切换：星星 0.7→1.15→1 弹入 + 触觉 `levelChange`。
- 删除：卡片 0.15s 缩小 + 淡出后再重排。
- 栈粘贴推进：栈角标 `popIn`。

### B3 声效（默认关闭）

- 新建 `SoundFeedback`（App 层）：`play(_ cue: Cue)`，`cue` 为 `.copy` / `.paste` / `.pin` / `.delete` / `.error`。
- 全部走系统 `NSSound(named:)`，**不引入外部音频资源**；取不到就静默跳过（不 beep）。
- 默认 **关闭**，设置页提供「操作音效」开关；开启后同 cue 200ms 内去重，避免连按刷音。
- 现有 4 处 `NSSound.beep()`（Pin 越界、Snip 失败、热键录制、Transfer 通知）保持原样，不纳入本开关。

### B4 触觉反馈

- 新建 `HapticFeedback`（App 层）：`tap(_ kind: Kind)`，`kind` 为 `.selection` / `.levelChange` / `.generic`，映射 `NSHapticFeedbackManager.defaultPerformer`。
- 接点：卡片选中切换、收藏切换、栈粘贴推进。默认开启，设置页提供开关。
- 无触控板时系统自行忽略，不做探测。

### B5 材质与渲染增强

1. 剪贴板面板：`.hudWindow` 底之上增加一层 `.underWindowBackground` 内衬（圆角 12、内缩 1pt），形成「面板 → 内容」两级材质；卡片内衬用 `controlBackgroundColor` 半透明，选中态叠 accent 5%。
2. 卡片阴影走 `CALayer.shadow*`（`shadowRadius` 6 / `shadowOpacity` 0.12 / offset (0,-1)），仅在 hover 与选中时出现，其余时间为 0；**不用离屏快照**，避免每帧重绘。
3. 缩略图就绪后 0.2s 淡入占位符号之上（`crossFade`），不再硬替换。
4. 设置窗口与截图贴图窗不引入材质（维持既有观感），只在剪贴板面板与设置页的卡片内衬统一圆角令牌。
5. `MenuPanel` 继续**不使用** `NSVisualEffectView`（既有决策 `MenuPanelView.swift:29-31`），本批不动。

## 4. 明确不做（登记 backlog）

| 项 | 理由 |
|---|---|
| 右键「搜索此内容」（Google 搜索） | 引入外部浏览器与网络依赖，与本地面板语义不符 |
| 新内容系统通知 + 未读角标 | 需新通知服务 + 权限 + 冷却策略，独立排期 |
| 9 类独立 kind / OCR / AI / 脚本 / Snippets / 标签 / 搜索历史 | OneClip 源码 0 命中，只有 README 宣称 |
| 面板读库改后台 / 分页 | 牵动搜索与方向键走满全量，单独排期 |
| 骨架屏 shimmer | 剪贴板同步读库无加载态，Token 页骨架已定稿 |
| 自定义音频资源 / 音效音量 | 用系统音，不引入二进制资源 |

## 5. 验收标准（派发前冻结）

**门禁**

| 组 | 命令 | 期望 |
|---|---|---|
| G-1 | `swift build --disable-sandbox --build-system native` | exit 0 |
| G-2 | `swift run --disable-sandbox --build-system native TestRunner` | 末行「🎉 所有测试通过！」 |
| G-3 | `swift build -c release --disable-sandbox --build-system native` | exit 0 |
| G-4 | `bash NetworkMonitor/Scripts/check-file-size.sh`（仓库根） | exit 0 |

**行为断言（TestRunner 新增）**

- A1：单文件 → `"<族>: <名>"`；多文件跨族顺序稳定；同族合并写法；路径含空格与中文不乱码；超长按条目边界截断且不出现半个文件名；空数组空串。
- A2：冷却期内 `shouldRetry` 为 false、过冷却为 true；达 `maxAttempts` 后终态 false；`markSucceeded` 清空；`reset` 清空。
- 其余（UI 动效 / 声效 / 材质）不做自动化断言，走快照与真机取证。

**体感验收（lead 自测）**

1. `NM_SNAPSHOT_DIR=/tmp/nm-l3 <可执行>` 出图，逐张核对：面板材质两级、卡片阴影、选中态。
2. 真机：开/收面板、悬停卡片看浮层、收藏、删除、栈粘贴各一次，确认动效不卡顿且「减弱动态效果」开启时全部落终态。
3. 声效默认静音；打开开关后复制/粘贴有提示音，连按不刷音。

## 6. 工程化要求

- 纯函数优先：摘要、重试策略下沉 `NetworkMonitorCore`；AppKit 依赖只留 App 层。
- 动效统一 `MotionKit`，禁止模块内另写 `CABasicAnimation`（`TransferMotion` 存量不动）。
- 主线程安全：所有动画与视图操作 `@MainActor`；后台回调回主线程。
- 可观测：编码 / 解码失败、重试放弃走 `LoggingService`（debug / warning），路径过 `LogRedaction`。
- 单文件 ≤ 500 行 / 15360 字节；单函数 ≤ 70 行。
- 范围固定：数据库 schema、卡片 176×198、面板宽度档位、菜单面板六页版式骨架四处不变。

## 7. 实现落点

分支 `clipboard-parity-3` 的实际落点（路径相对 `NetworkMonitor/Sources/`，逐条 `ls` 核对存在）：

| 规格项 | 落点文件 | 落地要点 |
|---|---|---|
| A1 文件条目分类聚合摘要 | `NetworkMonitorCore/Infrastructure/Clipboard/ClipboardFileSummary.swift`、`NetworkMonitor/Clipboard/PasteboardWatcher.swift`、`TestRunner/ClipboardFileSummaryTests.swift` | 纯函数 `summarize(paths:)` 与带回落文本的 `summarize(paths:fallbackText:)`；采集只改 `preview` 生成处，`text` 列仍存原始路径 |
| A2 缩略图多级兜底 + 失败可重试 | `NetworkMonitorCore/Infrastructure/Clipboard/ClipboardThumbnailRetryPolicy.swift`、`NetworkMonitor/Clipboard/ClipboardThumbnailLoader.swift`、`NetworkMonitorCore/Infrastructure/Clipboard/ClipboardThumbnailLoadGate.swift`、`NetworkMonitorCore/Infrastructure/Clipboard/ClipboardImageDecoder.swift`、`TestRunner/ClipboardThumbnailRetryPolicyTests.swift` | 策略负责冷却 30s 与上限 3 次；闸门只留并发 3 + 在途去重；解码在 ImageIO 之后接 `NSBitmapImageRep` → `thumbnail(from: CGImage)` 兜底，再退回原图直读 |
| A3 卡片悬停与全文浮层 | `NetworkMonitor/Clipboard/ClipboardCardView.swift`、`NetworkMonitor/Clipboard/ClipboardCardFullTextOverlay.swift`、`NetworkMonitor/Clipboard/ClipboardCardFlowView.swift` | hover 走 trackingArea + 0.45s 计时；浮层 `.hudWindow` 280pt / 最多 9 行、`ignoresMouseEvents`，超长内容的滚轮由卡片流转发（[踩坑](../踩坑/运行时/忽略鼠标事件的浮层自己收不到滚轮.md)） |
| A4 首次引导与快捷键帮助 | `NetworkMonitor/Clipboard/ClipboardPanelOverlays.swift`、`NetworkMonitor/Clipboard/ClipboardPanelSupport.swift`、`NetworkMonitor/Clipboard/ClipboardPanelController+Stack.swift`、`NetworkMonitor/Clipboard/ClipboardPreferences.swift`、`NetworkMonitor/Debug/SnapshotClipboardGuide.swift` | 引导态判定与一次性标记接线在控制器（库里有数据即视为已引导）；12 条键位是纯数据，界面与读屏共用一份；离屏取证入口 `NM_SNAPSHOT_CLIPBOARD_GUIDE` |
| B1 统一动效基础设施 | `NetworkMonitor/Motion/MotionKit.swift` | 时长令牌与 `TransferMotion` 同口径；跟随「减弱动态效果」，关闭时所有方法直接落终态 |
| B2 面板与卡片动效接线 | `NetworkMonitor/Clipboard/ClipboardCardFlowView+Motion.swift`、`NetworkMonitor/Clipboard/ClipboardCardView.swift`、`NetworkMonitor/Clipboard/ClipboardPanelController.swift` | 卡片进场前 12 张错峰、选中与 hover 走 `crossFade`、收藏星与栈角标 `popIn`、删除 0.15s 缩小淡出；面板展开收起见下方偏差 |
| B3 操作音效 | `NetworkMonitor/Feedback/SoundFeedback.swift`、`NetworkMonitor/AppCoordinator+Feedback.swift`、`NetworkMonitor/Settings/SettingsClipboardPane+Feedback.swift` | 只用 `NSSound(named:)` 系统音、默认关闭、同 cue 200ms 去重；开关每次调用现读偏好 |
| B4 触觉反馈 | `NetworkMonitor/Feedback/HapticFeedback.swift`、`NetworkMonitor/Feedback/ClipboardFeedback.swift`、`NetworkMonitor/Clipboard/ClipboardPanelController+Feedback.swift` | 选中切换 / 收藏切换 / 栈粘贴推进三个接点，默认开启，不做设备探测 |
| B5 材质与渲染 | `NetworkMonitor/Clipboard/ClipboardCardBackgroundView.swift`、`NetworkMonitor/Clipboard/ClipboardCardHighlightView.swift`、`NetworkMonitor/Clipboard/ClipboardCardThumbnailView.swift`、`NetworkMonitor/Clipboard/ClipboardCardContentView.swift` | 卡片底色半透明内衬 + 独立状态叠色层 + 缩略图 0.2s 淡入；阴影走视图 backing layer 的 `CALayer.shadow*`，只在 hover 与选中时非 0（取证口径见[踩坑](../踩坑/运行时/离屏快照里投影要靠像素差自证.md)） |
| P2-1 设置页存储管理 | `NetworkMonitor/Settings/SettingsClipboardPane+Storage.swift`、`NetworkMonitorCore/Infrastructure/Clipboard/ClipboardStorageUsage.swift`、`TestRunner/ClipboardStorageUsageTests.swift`、`NetworkMonitor/Debug/SettingsSnapshot.swift` | 占用（大小 + 条数）+ 打开目录 + 二次确认清空；统计只算目录第一层普通文件，清空后由组合根复用既有清空与孤儿清扫 |

为守住单文件体积上限，本轮还拆出下列文件，属改动的文件边界而非独立规格项：
`NetworkMonitor/Settings/SettingsClipboardPane+Permission.swift`（权限卡）、
`NetworkMonitor/Settings/SettingsClipboardPane+Feedback.swift`（操作反馈卡）、
`NetworkMonitor/AppCoordinator+ClipboardSettings.swift`（剪贴板设置页回调）、
`NetworkMonitor/Settings/SettingsWindow+Snapshot.swift`（设置窗快照入口）、
`NetworkMonitor/Clipboard/ClipboardCardFlowChrome.swift`（卡片流容器与空态）、
`NetworkMonitor/Clipboard/ClipboardCardFlowView+Thumbnails.swift`（缩略图接线）。

**实现期偏差与处置（2026-11-14 收口）**

- §3 B2「面板展开」已补齐：`MotionKit.stageWindowEntrance` / `fadeIn(window:toFrame:duration:)` / `fadeOut(window:duration:completion:)` 三个窗口级方法接管，控制器不再自写 `NSAnimationContext`（`Clipboard/ClipboardPanelController*.swift` 0 处）；`isEnabled == false` 时起始态直接落终态、`fadeOut` 同步回调 orderOut。敏感时序（先记前台 App → 再 `makeKeyAndOrderFront`）原样保留，动画只在成为 key 之后播放。
- §3 B5 第 1 条已补齐：`ClipboardPanelInnerMaterialView`（`.underWindowBackground`、圆角 12、相对面板边界内缩 1pt、`hitTest` 返回 nil）挂在面板内容视图首层，层次为 `.hudWindow` → 内衬 → 发丝分隔线 → 控件与卡片 → 浮层；父视图自绘的两条分隔线改为 `ClipboardPanelSeparatorView` 独立层（与改动前层次一致）。
- §3 B3 所列「现有 4 处 `NSSound.beep()`」实为 3 处（Pin 越界 / Snip 失败 / 热键录制）；互传通知走 `NSSound(named:)`，不是 beep。
- §2 A4 标为 P2、而本批另有一项记号同为 P2-1 的存储管理（来自取证表编号），两套编号不互通，引用时请写全称。

**仍存在的偏差（不粉饰）**

- 真机材质观感未取证：离屏 `cacheDisplay` 渲不出毛玻璃（见[踩坑](../踩坑/运行时/毛玻璃材质离屏不可辨.md)），浅色内衬近似色把面板底从 255 拉到 228（深色 30→58）；真机是 `.hudWindow` 垫底，观感需人工确认，离屏数值不作为调参依据。
- 「减弱动态效果」分支只做代码审阅（`MotionKit` 三处 `isEnabled` 守卫），未在系统开关下运行时验证（不改系统辅助功能设置触发不到）。
- 动效本体（0.18s 淡入 + 14pt 位移回落）无法用静态快照取证，只有接线与代码。
- 内衬挂在内容视图而非控制器：层次等价（内容视图自身不绘底色），代价是「面板 chrome 在控制器」的直觉被打破，理由写在 `ClipboardPanelChrome.swift` 头部。

## 8. 验收记录（2026-11-14）

**门禁（最终代码，原始末行）**

| 组 | 结果 |
|---|---|
| G-1 `swift build --disable-sandbox --build-system native` | exit 0，`Build complete! (3.59s)` |
| G-2 `swift run --disable-sandbox --build-system native TestRunner` | exit 0，末行「🎉 所有测试通过！」 |
| G-3 `swift build -c release --disable-sandbox --build-system native` | exit 0，`Build complete! (26.69s)` |
| G-4 `bash NetworkMonitor/Scripts/check-file-size.sh` | exit 0，已检查 556 个文件 |

**快照与结构自证**（`NM_SNAPSHOT_DIR=/tmp/nm-l6-motion`；基线 `/tmp/nm-l6-baseline` 为改动前源码构建，已用 `strings` 核对不含 `ClipboardPanelSeparatorView`）

- 图：`panel-clipboard-light.png` / `panel-clipboard-dark.png` / `nm-corner-{light,dark}.png`（角部 8× 放大）
- `structure.txt`：探针编译真实 `ClipboardPanelChrome.swift`，14 项运行时断言全 PASS —— material / blendingMode / state / 圆角 12 / 内缩 1pt / autoresizing / `hitTest == nil` / 640×260 与 520×200 两档 frame / 分隔线纵坐标 [32, 236]
- `metrics.txt`：直边逐像素「外层 1pt 环 → 内衬」，色调差 27（浅）/ 28（深）；卡片内部四点 `246/40` 与基线逐值相同；选中描边 bbox 与蓝色像素数（浅 1228 / 深 1100）与基线一致（布局零位移）；阴影相对深度 3.9% / 3.4% 未变

**未覆盖（转人工/后续）**：真机毛玻璃观感、「减弱动态效果」开关下的运行时表现、动效本体的动态观感（见上文残留偏差）。
