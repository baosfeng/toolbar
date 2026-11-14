# macOS 27 与 Swift 6.4 能力盘点

> **何时阅读：** 评估能否抬 `swift-tools-version` / `Package.swift` 平台版本、接入 macOS 26/27 新 API（玻璃、菜单栏展开界面、截图、视觉），或调整构建管线（优化开关、打包墙钟）时。
>
> 勘察时间：2026-11-14 · 仓库 `/Users/bsfeng/IdeaProjects/toolbar`（worktree `chore/ci-pipeline`，基线 main `98d8eaf`）
>
> 本机环境：macOS 27.0.1（26A434）/ SDK 27.0 / Swift 6.4 / **仅 Command Line Tools（无 Xcode.app）**
>
> 证据口径：仓库侧符号与正文检索走 `codebase-memory-mcp cli`（项目 `Users-bsfeng-IdeaProjects-toolbar`，7783 节点 / 35914 边）；SDK 结论取自 `xcrun --show-sdk-path`（`/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`，即 `MacOSX27.0.sdk`）下的头文件与 `.swiftinterface`；构建耗时与产物体积为本机实测。

## 一、结论速览

| 项 | 结论 | 依据 |
|---|---|---|
| 本机工具链 | Swift 6.4（`swiftlang-6.4.0.34.1`）+ SDK 27.0，**只有 CLT、没有 Xcode.app** | `swift --version` / `xcrun --show-sdk-version` / `xcodebuild -version` 报缺少 Xcode |
| CI 工具链 | GitHub `macos-26` runner：默认 Xcode 26.6（17F113），SDK 最高 macOS 26.5，**没有 Xcode 27** | `actions/runner-images` 的 `macos-26-arm64-Readme.md` |
| `swift-tools-version` 抬到 6.4 | **不能抬**：CI 的 Swift 6.3.x 会直接拒绝，CI 与 Release 双红 | 见 §5.1 |
| 本机用 6.4 编译 | **可用**：现有 `tools-version: 6.3` 包在 Swift 6.4 下 debug / release 均构建通过（仅 1 条 `--build-system native` deprecated 警告） | 本机实测 |
| 默认构建后端 | **仍必须传 `--build-system native`**：Swift 6.4 默认后端在 CLT-only 环境同样 `SessionFailedError / Unknown error parsing property list` | 本机实测（0.85 s 失败） |
| 玻璃 | `NSGlassEffectView` / `NSGlassEffectContainerView` = macOS 26.0；`effectIsInteractive` 单独 = **27.0**；`NSVisualEffectView` 26/27 无新 material | SDK 头文件 + 既有勘察文档 |
| 菜单栏 | macOS 27 新增 `NSStatusItem.expandedInterfaceDelegate` / `expandedInterfaceSession`（自定义展开面板的官方生命周期） | `NSStatusItem.h` |
| 通知 | UserNotifications 在 SDK 26/27 **没有新增 API**（分组/图标是系统行为） | 全 Headers 无 `macos(26/27` 标注 |
| 截图 API | ScreenCaptureKit 27 新增 `isCapturing`、`SCClipBufferingOutput`、`SCContentSharingPicker.present(from:)`、`SCScreenshotDisplayIntent` | SCK Headers |
| 视觉 | Vision 26 起有 Swift 新 API：`RecognizeTextRequest`、`RecognizeDocumentsRequest` | Vision `.swiftinterface` |
| 优化开关 | `-Osize` 编译通过、产物 **−2.74%**；`-cross-module-optimization` 编译通过、产物 **+3.13%**；耗时差异在噪声区间 | §5.2 实测 |
| 打包墙钟 | 全部集中在 `swift build`（release 全量约 130 s）；打包 + 签名是秒级 | §6 |

## 二、本机工具链实况

命令与实测输出（2026-11-14，本机）：

```text
$ swift --version
swift-driver version: 1.168.6 Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)
Target: arm64-apple-macosx27.0.0

$ swift package --version
Swift Package Manager - Swift 6.4.0-dev

$ xcodebuild -version
xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory
'/Library/Developer/CommandLineTools' is a command line tools instance

$ xcode-select -p
/Library/Developer/CommandLineTools

$ xcrun --show-sdk-version --sdk macosx
27.0
$ xcrun --show-sdk-path --sdk macosx
/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk

$ sw_vers
ProductName: macOS   ProductVersion: 27.0.1   BuildVersion: 26A434

$ ls /Library/Developer/CommandLineTools/SDKs
MacOSX.sdk  MacOSX12.1.sdk  MacOSX12.3.sdk  MacOSX26.5.sdk  MacOSX26.sdk  MacOSX27.0.sdk  MacOSX27.sdk
```

- 本机 SDK 指向 27.0；同时保留 26.5 / 26 两代 SDK，可用 `-sdk` 指定旧 SDK 做兼容编译验证。
- 没有 `/Applications/Xcode*.app`，`xcodebuild` 与默认 SwiftPM 后端均不可用（见 §5.3）。
- 仓库现有文档里有一处旧记录写「Swift 6.3」（`docs/调研/主题与玻璃拟态勘察.md` 头部），本机实际是 6.4，以本节为准。

## 三、macOS 26 / 27 新 API 清单（按对本项目的价值排序）

### 3.1 值得接入的 Top 5

| # | API | 可用版本门槛 | 仓库现状 | 接入价值 | 风险 |
|---|---|---|---|---|---|
| 1 | `NSStatusItem.expandedInterfaceDelegate` + `NSStatusItemExpandedInterfaceSession`（`NSStatusItemExpandedInterfaceDelegate` 协议：`statusItem(_:didBeginExpandedInterfaceSession:)` / `statusItemDidEndExpandedInterfaceSession(_:animated:)`） | **macOS 27.0** | `MenuBarManager.swift:14,69` 用 `NSStatusItem` + 自管 target/action 弹 `NSPopover`，未用该协议 | 高：把「点状态项弹自定义面板」从手写 toggle 换成系统生命周期，可参与键盘导航、菜单跟踪、点外部自动收起；面板收起时机由系统回调统一 | 27 才可用，需 `@available` 分支；与现有 target/action 并存时要防双触发；面板不再是 `NSPopover` 时要自己摆窗口位置 |
| 2 | `NSGlassEffectView`（`contentView` / `cornerRadius` / `tintColor` / `style: .regular|.clear`）+ `NSGlassEffectContainerView`（`spacing` 临近合并、批量渲染）+ `effectIsInteractive` | **26.0**（栈）；`effectIsInteractive` **27.0** | 0 引用（现用 `NSVisualEffectView` 3 处） | 高：面板/弹窗的 Liquid Glass 直接抓手；容器可减少重复玻璃 pass | 平台最低版本现为 `.v14`，用前必须 `@available(macOS 26, *)` 分支或抬平台；每屏十几个玻璃层会掉帧，卡片仍建议半透明自绘；`effectIsInteractive` 只给带控件的弹窗 |
| 3 | ScreenCaptureKit 27：`SCStream.isCapturing`、`SCClipBufferingOutput`（`addClipBufferingOutput` / `removeClipBufferingOutput`）、`SCContentSharingPicker.present(from:window:)`、`SCScreenshotDisplayIntent`（HDR 截图）、`SCStreamFrameInfoVideoOrientation` | **27.0**（26.0 另有 `SCStreamConfigurationPresetCaptureHDRRecordingPreservedSDRHDR10`） | `Snip/ScreenCaptureService.swift` 已用 `SCScreenshotManager`；`Debug/SnipVisibleProbe.swift` 复用同一套 | 中高：`isCapturing` 让「是否正在截」有官方查询；`SCContentSharingPicker.present(from:)` 省自定义 picker 挂载；HDR 截图可提升视网膜/HDR 屏截图质量 | 27 才可用；截图模块已有自绘覆盖层与历史选区，新 picker 可能与现有交互冲突；HDR 需按显示器能力回退 |
| 4 | `NSView.cornerConfiguration` / `effectiveCornerRadii` / `viewDidChangeEffectiveCornerRadii()` / `invalidateCornerConfiguration()` + `NSViewCornerConfiguration`（`corners(radius:)` / `corners(topLeftRadius:…)` / `capsule` / `uniformCorners`） | **27.0** | 0 引用；现有圆角靠 `PaneCardStyle` 常量（卡片 9pt、面板 12pt）与自绘路径 | 中：可让面板/卡片跟随容器做 concentric 圆角，省自绘与手算 | 27 才可用；项目已有一套稳定的自绘圆角，切换需要逐页回归；`NSViewCornerRadii` 与自绘 `cornerRadius` 混用易出现双圆角 |
| 5 | Swift 6.4 语言能力：`@diagnose`（SE-0522，源码级告警抑制/提升）、`async defer`（SE-0493，defer 内可 await）、`withTaskCancellationShield`（SE-0504，清理工作不被取消）、可选 `some/any` 括号省略（SE-0521） | **编译器 6.4**（无 OS 门槛） | 未用；`非isolated` / `Sendable` 治理已有一轮（`a8dc3d5` 清零 43 条告警） | 中：`@diagnose` 可把「已知噪音」精确抑制到一行，避免全局 `-warnings-as-errors` 被一条告警卡死；取消盾适合清理/落盘路径 | **CI 的 Swift 6.3 不识别这些语法**，只能在「不加进仓库」的前提下用于本机试验；要落地必须等 CI 升级工具链 |

### 3.2 玻璃/材质准确门槛表（给玻璃接入方直接引用）

SDK 头文件 `AppKit/NSGlassEffectView.h`（Copyright 2025）实测：

| API | 门槛 | 说明 |
|---|---|---|
| `NSGlassEffectView` | `API_AVAILABLE(macos(26.0))` | 类；`contentView` 是唯一保证嵌进玻璃的视图，其余子视图不保证 z 序 |
| `NSGlassEffectViewStyle`（`.regular` / `.clear`） | macos(26.0) | `NS_SWIFT_NAME(NSGlassEffectView.Style)` |
| `NSGlassEffectView.cornerRadius` / `tintColor` / `style` | macos(26.0) | — |
| `NSGlassEffectView.effectIsInteractive` | **macos(27.0)** | 默认 `NO`；只应在「玻璃作为交互控件背景或容器」时开 |
| `NSGlassEffectContainerView`（`contentView` / `spacing`） | macos(26.0) | 临近合并同类玻璃、批量渲染降 pass；`spacing` 默认 0 只做批量不做合并 |
| `NSVisualEffectView` 新 material | **无** | 26/27 没有新增 material case，Liquid Glass 只能在 `NSGlassEffectView` 上做 |

> 既有勘察（`docs/调研/主题与玻璃拟态勘察.md` §2.5）已给出同一结论；本表仅补齐「`effectIsInteractive` 是 27 而不是 26」这一条门槛，玻璃接入方按此表写 `@available` 分支即可。

### 3.3 菜单栏相关（27）

| API | 门槛 | 价值 | 风险 |
|---|---|---|---|
| `NSStatusItem.expandedInterfaceDelegate`（`id<NSStatusItemExpandedInterfaceDelegate>`，weak） | 27.0 | 状态项不用 `NSMenu` 而定位自有窗口时，由系统驱动「开始/结束展开界面」，参与键盘导航与菜单跟踪；点外部等行为可统一 | 与现有 target/action 并存会双触发；面板生命周期的状态机要重写 |
| `NSStatusItem.expandedInterfaceSession`（readonly，`NSStatusItemExpandedInterfaceSession`，仅 `cancel()`） | 27.0 | 与 delegate 配套；自定义收起时可主动 `cancel()` 让系统同步状态 | `cancel()` 会触发 delegate 回调，注意重入 |
| `NSMenuItem.preferredImageVisibility`（`NSMenuItem.ImageVisibility`: `automatic` / `visible` / `hidden`） | 27.0 | 菜单项图标在系统「隐藏图标」配置下仍可强制显示 | 系统仍可能覆盖；只影响菜单打开态 |

### 3.4 通知（UserNotifications）

- SDK 26 / 27 的 `UserNotifications.framework/Headers` **没有任何 `API_AVAILABLE(macos(26|27` 标注**：通知分组、声音、图标等能力没有新 API，仍走 `UNNotificationSound` / `UNNotificationCategory` / `UNNotificationAttributedMessageContext` 等既有类型。
- 仓库现有两处 `UNUserNotificationCenter`（`Transfer/TransferNotification.swift:21`、`Billing/BillingAlertService.swift:28`）无需为 26/27 改动。
- 结论：本块没有「接入新特性」的增量，改动收益只在业务侧（提醒文案/分组策略），不在 API 层。

### 3.5 截图与视觉

ScreenCaptureKit（Headers，`macos(27` 标注）：

| API | 门槛 | 价值 |
|---|---|---|
| `SCStream.isCapturing` | 27.0 | 官方查询「流是否活跃」，替代自己维护布尔 |
| `SCClipBufferingOutput` + `addClipBufferingOutput:error:` / `removeClipBufferingOutput:error:` | 27.0 | 剪辑缓冲（每流仅一个会话），可用于「最近 N 秒回放」类功能 |
| `SCContentSharingPicker.present(from:window:completionHandler:)` | 27.0 | 从指定窗口弹出系统共享选择器，省自定义挂载 |
| `SCScreenshotDisplayIntent`（`SCScreenshotDisplayIntentLocal` 等） | 27.0 | 指定截图落在哪个显示器（HDR / 本机显示） |
| `SCStreamFrameInfoVideoOrientation` | 27.0 | 帧信息带方向，旋转屏截图不必自己推断 |
| `SCStreamErrorInsufficientStorage` / `SCStreamErrorNotSupported` | 27.0 | 录屏错误可细分 |
| `SCStreamConfigurationPresetCaptureHDRRecordingPreservedSDRHDR10` | 26.0 | HDR 录制同时保留 SDR/HDR10 表现 |

Vision（`.swiftinterface`，`@available(macOS 26.0)`）：

- `RecognizeTextRequest`：26 起的新 Swift OCR API（替代旧 `VNRecognizeTextRequest` 路径），结果含 `recognitionLanguages`、`textDirection`、`boundingRegion`。
- `RecognizeDocumentsRequest` → `DocumentObservation`（文档结构、标题层级、表格），适合「截图里的表格/文档」类需求。
- 27 追加 `GenerateIterativeSegmentationRequest`、`RecognizeAnimalsRequest.Identifier` 扩展、`DownloadableAssetsRequest`（可下载模型状态）。
- 仓库现状：`RecognizeTextRequest` / `VNRecognizeText` **0 命中**（当前没有 OCR）。若要做「截图取字 / 剪贴板图片转文字」，从 26 的 `RecognizeTextRequest` 起就是最短路径；26 以下回落到旧 Vision 接口。

### 3.6 面板与控件（AppKit 26/27，价值中等）

| API | 门槛 | 备注 |
|---|---|---|
| `NSBezelStyle.glass` | 26.0 | 玻璃质感按钮（`NSBezelStyleGlass = 16`） |
| `NSControlBorderShape`（`borderShape`） | 26.0 | 控件边框形状统一到系统口径 |
| `NSToolbarItem.style` / `NSToolbarItem.Style`、`backgroundTintColor`、`badge` | 26.0 | 设置窗口工具栏可贴系统样式 |
| `NSImage.SymbolColorRenderingMode` / `SymbolVariableValueMode` | 26.0 | SF Symbol 颜色/可变值渲染（菜单栏图标） |
| `NSControlSize.extraLarge` | 26.0 | 大号控件 |
| `NSApplication.PresentationOptions.disableScreenCornerInteractions` | 27.0 | 全屏/演示时允许点屏幕角 |
| `NSSegmentedControl.Role` / `role` | 27.0 | 分段控件语义角色（换 tab 表达） |
| `NSView.exclusiveGestureBehavior` / `NSView.ExclusiveGestureBehavior` | 27.0 | 手势互斥策略（截图标注层可参考） |
| `NSBrowser` 27 拖拽回调 | 27.0 | 与项目无关 |

### 3.7 系统监控

- `IOKit.framework/Headers` 与 `ServiceManagement.framework/Headers` **没有 `macos(26|27` 新增**；`IOReport` 仍无公开头文件（仓库 `SystemGPUPowerReader` 等 10 处命中都是私有符号的 dlsym 用法），26/27 没有新增可公开调用的 IOReport 接口。
- `sysctl` 新项没有 SDK 层可枚举清单，若要扩展指标仍按现有「可读则用、不可得降级为 —」策略。
- 结论：系统监控块没有「白捡」的新 API，下一轮扩展仍要按私有接口探测 + 降级。

### 3.8 其他（与本项目无关，记录以免重复调研）

- CoreGraphics 27 新增集中在 PDF 结构化（`CGPDFStructureElement` / `CGPDFMarkedContentItem` / `CGContext.beginMarkedContentSequence`），本项目无 PDF 输出。
- Foundation 26 有 `AttributedString` 的 `filter(inheritedByAddedText:)` / `transform(updating:)` 等，26/27 未见与当前功能相关的增量。
- AppKit 27 的 HDR 内容抑制（`applicationShouldSuppressHighDynamicRangeContent`）等属系统层行为，与菜单栏应用无直接关系。

## 四、代码现状核对（codebase-memory）

| 关键字 | 命中 | 位置 |
|---|---|---|
| `NSStatusItem` | 1 个模块 | `MenuBarManager.swift:14,69`（状态项 + `NSPopover` 面板） |
| `NSGlassEffect` | 0 | — |
| `NSVisualEffectView` | 3 处 | `Clipboard/ClipboardPanelController.swift:94-95`、`MenuPanel/MenuPanelView.swift:29`、`Debug/SnapshotCanvas.swift:36` |
| `ScreenCaptureKit` / `SCScreenshotManager` | 3 个文件 | `Snip/ScreenCaptureService.swift:162-179,197-216`、`Debug/SnipVisibleProbe.swift:23-50` |
| `RecognizeTextRequest` / `VNRecognizeText` | 0 | 无 OCR |
| `UNUserNotificationCenter` | 2 | `Transfer/TransferNotification.swift:21`、`Billing/BillingAlertService.swift:28` |
| `IOReport` | 10 | `SystemMetrics/SystemGPUPowerReader.swift:141` 等（私有符号） |
| `NSPopover` | 8 | `MenuBarManager.swift:10`、`Snip/SnipController.swift:152` 等 |

> 注：知识图谱对 `MenuPanel/` 等 28 个文件标了 `parse_partial`（tree-sitter 错误恢复），上述「0 命中」结论已用正文检索交叉确认；若后续新增代码，重新 `index_repository` 后再核对。

## 五、编译器升级评估

### 5.1 `swift-tools-version` 能否抬到 6.4：**不能，保持 6.3**

依据链（三条都能复核）：

1. **CI runner 没有 Swift 6.4**：`actions/runner-images` 的 `macos-26-arm64-Readme.md` 显示 runner 默认 Xcode 26.6（17F113），可用 SDK 表最高 `macosx26.5`（对应 Xcode 26.5 / 26.6）；Xcode 27 只有 public preview 公告，未预装。Xcode 26.6 自带的是 Swift 6.3.x，因此 `swift build` 拿到的工具链是 6.3.x。
2. **SwiftPM 对 tools-version 是硬门禁**：包声明高于工具链时会直接失败。本仓历史上有同类报错记录（`docs/开发指南/构建与测试.md` §双架构发版、提交 `9cb251c`）：`using Swift tools version 6.3.0 but the installed version is 6.1.0`。抬到 6.4 后，`ci.yml` 的 `Build (debug, with test targets)` 与 `release.yml` 的 `build-app.sh` 都会在第一步红。
3. **本机 6.4 只能证明「不必降级」**，不能证明「CI 能跟上」：本机 debug / release 构建都在 `tools-version: 6.3` 下通过（见 §6 的耗时数字），说明 6.4 编译器向下兼容 6.3 的包；反向不成立。

**做法（推荐）**：`Package.swift` 保持 `// swift-tools-version: 6.3`；本机用 6.4 编译天然可用；要吃到 6.4 语言特性，等 runner 镜像升级到 Xcode 27（或改用 `macos-27` 标签，届时再抬）。

**兼容写法**：代码只用 6.3 支持的语法（现状即如此），6.4 与 6.3 双工具链都能编；6.4 专属语法（`@diagnose`、`async defer`、`withTaskCancellationShield`、`some T?` 简写、`Module::Type` 选择器）在 6.3 上会直接报错，因此**不要写进仓库源码**，只能在本地试验分支里验证。

### 5.2 优化开关实测（`swift build -c release`，本机 arm64）

测试方法：每次先 `rm -rf .build/arm64-apple-macosx/release` 做全量，再 `/usr/bin/time -p swift build -c release --disable-sandbox --build-system native <flag>`；产物体积取 `.build/arm64-apple-macosx/release/NetworkMonitor`。

| 配置 | 编译结果 | 墙钟（real） | 产物体积 | 相对基线 |
|---|---|---|---|---|
| 基线（默认 `-O`） | 通过 | 129.69 s | 8,015,888 B | — |
| `-Xswiftc -Osize` | **通过** | 115.46 s | **7,796,144 B** | **−2.74%** |
| `-Xswiftc -cross-module-optimization` | **通过** | 118.73 s | 8,267,072 B | +3.13% |
| `-Xswiftc -enable-upcoming-feature -Xswiftc ExistentialAny` | 通过（产生告警） | 120.44 s | 未单独记录 | 不是优化开关，反而多告警 |
| `swift build -c release --product NetworkMonitor` | 通过 | 130.60 s | 8,015,888 B | 无收益（见 §6） |
| 默认构建后端（不带 `--build-system native`） | **失败** | 0.85 s | — | `SessionFailedError / Unknown error parsing property list` |

说明：

- 墙钟差异（115–130 s）落在系统负载噪声区间（测量期间并行跑了 SDK 检索），不能据此断言某 flag 更快；**体积差异是稳定信号**。
- `-Osize` 可以加，代价是极端场景下性能略降（体积换速度），建议只在「体积敏感」的发布配置里试，默认仍用 `-O`。
- `-cross-module-optimization`（等价 `-enable-default-cmo`）能让 release 产物略提性能，但体积 +3.1%、且把增量编译退化为近似全量，**不推荐默认开**。
- `ExistentialAny` 只证明该 upcoming feature 在 6.4 下可用（当前是 warning），6.3 是否支持未验证，且会新增告警 → 不加。
- 6.4 独有的 `-enable-experimental-feature` 名字与 6.4 语言特性在 6.3 工具链上不可用，因此不作为可落地项。

### 5.3 构建后端：`--build-system native` 仍需保留

Swift 6.4 的 SwiftPM 把「Swift Build」设为默认构建系统，但在**只有 CLT 的本机**仍然失败：

```text
$ swift build -c release --disable-sandbox
error: SessionFailedError(... "Unknown error parsing property list" ...)
```

这与 `docs/开发指南/构建与测试.md` 记录的旧故障一致：默认后端需要完整 Xcode（XCBuild 组件）。所以：

- 本机命令继续追加 `--build-system native`（会有一条 deprecated 警告，可接受）。
- CI runner 有完整 Xcode，用默认后端（`build-app.sh` 里 `BUILD_SYSTEM=default`）仍是正确选择，两条路径各自保留。

## 六、build-app.sh 现状与优化建议（只读分析，未改动）

本机打包墙钟实测（release 配置）：

| 阶段 | 耗时 | 占比 |
|---|---|---|
| `swift build -c release`（全量，native 后端） | 129.69 s | ≈100%（绝对瓶颈） |
| 增量构建 + 建 `.app` + 拷二进制/图标 + 写 Info.plist + `codesign`（`SKIP_INSTALL=1` 整条脚本实测） | **1.21 s** | 秒级 |
| `ditto` 打 zip（CI 步骤，产物 2.2 MB） | ≈0.3 s | 可忽略 |
| 部署到 `/Applications`（仅非 SKIP_INSTALL） | 秒级（含杀旧进程轮询 sleep ≤2 s） | 与代码无关 |

**建议（按收益排序）**：

1. **并行双架构用独立 scratch 目录**：本机要同时出 arm64 / x86_64 时，两个 `swift build` 进程会争用同一 `.build` 的 `build.db`；改用各自 `--scratch-path`（如 `.build-arm64` / `.build-x86_64`）后可并行，墙钟从 `2×130 s` 降到约 `130–160 s`（受 CPU 与内存约束，release 单进程峰值 RSS ≈1.5 GB）。
2. **缓存编译产物、复用增量**：本机全量 release 130 s，而增量构建只需秒级（debug 同口径实测 0.57 s「无变化」/ 29.5 s「全部源码 mtime 刷新」）；CI 侧已加 `.build/<arch>-apple-macosx` 缓存（见 `ci.yml` / `release.yml`），本机日常部署实际墙钟 ≈ 打包 + 签名，不再是分钟级。
3. **签名按层签、去掉 `--deep`**：`sign_app` 现在用 `codesign --force --deep`；Apple 推荐逐层签名（先 `Contents/MacOS` 再包体），既更快也更不容易在 `.app` 内含框架后出错。改动小、与品牌改名无冲突，等该批次合并后可顺手做。
4. 顺带确认：`--product NetworkMonitor` **不省时间**（130.60 s vs 129.69 s），TestRunner 编译只占其中很小一部分，不必为此改脚本。真正要提速只能并行或命中缓存。

## 七、推荐落地顺序

1. **现在就能做（不阻塞 CI）**：`@available(macOS 26/27, *)` 分支接入玻璃（玻璃接入方已在进行）与 `NSStatusItem` expanded interface；保持 `tools-version: 6.3`。
2. **等 CI 镜像升级到 Xcode 27**：抬 `swift-tools-version` 到 6.4，同时启用 `@diagnose` 做告警治理，并评估 `withTaskCancellationShield` 用于清理路径。
3. **体积敏感时**：release 加 `-Xswiftc -Osize`（实测 −2.74%）。
4. **不推荐**：默认开 `-cross-module-optimization`（体积 +3.1% 且拖慢增量）；`--product` 优化（无收益）。

## 八、附录：可复跑命令

```bash
# 工具链
swift --version; swift package --version
xcrun --show-sdk-version --sdk macosx; xcrun --show-sdk-path --sdk macosx
xcode-select -p; sw_vers

# 玻璃门槛
grep -n "NSGlassEffect\|effectIsInteractive" \
  /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/AppKit.framework/Versions/C/Headers/NSGlassEffectView.h

# 菜单栏 27
grep -n "macos(27" \
  /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/AppKit.framework/Versions/C/Headers/NSStatusItem.h

# 各框架 27 新增计数
for fw in /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/*.framework; do
  n=$(grep -rh "API_AVAILABLE(macos(27" "$fw/Versions/"*/Headers 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" -gt 0 ] && echo "$n $(basename $fw)"
done | sort -rn

# release 全量计时 + 体积
cd NetworkMonitor && rm -rf .build/arm64-apple-macosx/release
/usr/bin/time -p swift build -c release --disable-sandbox --build-system native
ls -l .build/arm64-apple-macosx/release/NetworkMonitor
```
