# 截图时 Dock 出现本应用图标

> **何时阅读：** 菜单栏（`LSUIElement`）App 在截图 / 另存为 / 启动阶段突然在 Dock 里冒出一个图标
> （用户口径：「每次我们截图的时候，都会出现我们的软件出现在 dock 栏」）。

## 问题描述

本应用是 `LSUIElement` 菜单栏 App（`main.swift` 起手 `setActivationPolicy(.accessory)`），
正常状态下 Dock 里只有用户自己钉住的「一览」快捷方式，没有运行中的第二个图标。
但截图链路里有三处把激活策略切成 `.regular`，而 `.regular` 的定义就是「出现在 Dock」：

| 位置 | 时机 | Dock 可见时长（实测） |
|------|------|----------------------|
| `AppCoordinator+Snip.swift` 启动预热 | 启动后 1.5s，持续 1.2s | 约 2.4–2.7s |
| `SnipController+Overlay.swift` `claimForegroundForCapture()` | 每次抓屏前 | 覆盖层整个生命周期 |
| `SnipOverlayWindow.swift` `enterInteractiveMode()` | 覆盖层上屏 | 同上（与上一处叠在一起） |
| `SnipController+Export.swift` `presentSavePanel()` | ⌘S 另存为 | 面板整个生命周期 |

为什么当初会切：`.accessory` 下 `NSApp.activate` 常常「返回成功但前台没交过来」，
键盘事件继续投给原前台，表现为 Esc / 回车时灵时不灵。切 `.regular` 后系统才真的把前台交过来。
也就是说这条捷径是拿「Dock 图标闪一下」换「键盘稳定」。

## 解决方案

**不切策略**：截图需要的只是「覆盖层收到键盘」，而覆盖层是 `NSPanel` + `.nonactivatingPanel`
+ `canBecomeKey = true`（贴图窗 `PinWindow` 一直是这个形态）。这种窗口 `makeKey()` 之后
本身就是 key window，`keyDown` 直接派给视图，与 App 是不是 `.regular` 无关。

- `Snip/SnipForegroundPolicy.swift`：抢前台 / 归位的**唯一出口**，只做 `activate` 与兜底归位，
  一处都不写 `setActivationPolicy(.regular)`；
- `claimForegroundForCapture()` / `enterInteractiveMode()` / `presentSavePanel()` 全改走它；
- 启动预热整段下线：它存在的唯一目的就是替截图付掉那次「策略迁移」，不切策略就没有迁移要付；
- 首次按键仍由两条既有兜底接住：覆盖层的有限次激活重试 + `CGEventTap`（白名单吞键）。

实测（macOS 27 / 单屏）：`.accessory` 下覆盖层 `isKeyWindow=true`，
方向键（键码 123/124/125）能移动选区、Esc 能取消、另存为面板 `isKeyWindow=true`。

## 如何识别

- 策略判据不能读 `lsappinfo info -only ActivationPolicy <pid>`：本机（macOS 27）该 key 不存在，
  整行返回 `[ NULL ]`；能读到的是 `-only ApplicationType`（`UIElement` vs `Foreground`）。
- 用户可见后果用 Dock 的 AX 树读：`AXUIElementCreateApplication(dock pid)` → 首个子项（`AXList`）
  → `AXChildren`，数 `AXTitle == AppIdentity.displayName` 的条目；
  钉住的那一项 `AXIsApplicationRunning == 0`，运行中出现的那一项为 `1`。
- 自证探针：当时用 `NM_SNIP_DOCK_PROBE=1 <打包内的可执行文件>` 走完一次真实截图（含另存为面板），
  逐相位打印 `policy` 与 `dockItems`，任一采样点不是 `.accessory` 或 Dock 条目变多即 exit 1；
  `=wait` 等外部真实按键取消、`=keys` 自证方向键改了选区。**该探针已随 `Debug/` 删除**，
  今天复验只能手测（按一次 ⌃⇧S 走完另存为）并对照 Dock 的 AX 树；运行期判据另有 `SnipDockIconPolicyTests` 守着。

## 历史残留：修好之后 Dock 里仍有一条「一览」

改完上面这些，**运行中的图标**不会再出现，但 2026-11 用户仍反馈「Dock 里有一览」。
查下来是另一回事：Dock 的**「最近应用」区**里挂着一条历史记录，与 `.accessory` 无关。

- 记录位置：`~/Library/Preferences/com.apple.dock.plist` 的 `recent-apps`（本次实测 `[0]` 就是
  `com.bsfeng.yilan`，`tile-data.file-label = 一览`）。Dock 的 AX 列表里它排在
  「系统设置 / OpenIDEA」之后、废纸篓之前 —— 也就是最近应用那一段。
- 为什么会进去：`recent-apps` 记的是**通过 LaunchServices 启动过**的应用（`open`、Finder 双击、
  登录项拉起），跟 `LSUIElement` 毫无关系。1.28 及更早截图时切 `.regular`，那段时间把它登记了进去。
- **后续不会再涨**（实测）：`open -n /Applications/一览.app` 起第二个实例后，
  `recent-apps` 的条数、顺序、GUID（`4053037509`）**一个都没变** ——
  纯 `.accessory` 的启动不会登记进最近应用。
- **存量不会自己消失**：它不是运行态图标，是一个 plist 记录，登录 / Dock 重启都不会清掉。
  要清就得动一次：`defaults delete com.apple.dock recent-apps && killall Dock`
  （会顺带清掉其他 app 的最近记录；系统会重新积累，不必备份）。
- macOS 没有 per-app 的「别把我放进最近应用」开关，只有全局的
  `defaults write com.apple.dock show-recents -bool false`。

### 怎么区分两种「Dock 里的一览」

| 判据 | 运行中泄漏（本文上半部分） | 最近应用残留（本节） |
|------|--------------------------|---------------------|
| `lsappinfo` 的 `ApplicationType` | 泄漏瞬间是 `Foreground` | 始终 `UIElement` |
| Dock AX 项 `AXIsApplicationRunning` | `1` | `0` |
| 是否会在操作时闪现 | 会（截图 / 另存为 / 启动） | 不会，一直静挂在那里 |
| 处置 | 改代码，别切 `.regular` | 清一次 `recent-apps` |

## 已知限制

- 「Dock 图标是否出现」只能在真实登录会话里验：锁屏 / 无头环境没有 WindowServer，也读不到 Dock AX。
  发版前请用打包后的 .app 跑一次探针，不要用裸二进制（会崩在 UserNotifications）。
- Dock 的 AX 条目有几十毫秒的滞后：探针按 20–50ms 轮询足够抓到几百毫秒以上的泄漏，
  但抓不到只存在一两帧的极端情况。

## 参考文件

- `NetworkMonitor/Sources/NetworkMonitor/Snip/SnipForegroundPolicy.swift`
- `NetworkMonitor/Sources/NetworkMonitorUI/SnipActivationPolicy.swift`（审计判据，可单测）
- ~~`NetworkMonitor/Sources/NetworkMonitor/Debug/SnipDockProbe.swift`~~（`NM_SNIP_DOCK_PROBE`，已随 `Debug/` 删除）
- `NetworkMonitor/Sources/TestRunner/SnipDockIconPolicyTests.swift`（运行期判据 + 源码守卫）
- `NetworkMonitor/Sources/NetworkMonitor/Snip/SnipOverlayWindow.swift`
- `NetworkMonitor/Sources/NetworkMonitor/Snip/SnipController+Overlay.swift`
