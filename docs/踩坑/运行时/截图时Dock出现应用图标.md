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
- 自证探针：`NM_SNIP_DOCK_PROBE=1 <打包内的可执行文件>` 走完一次真实截图（含另存为面板），
  逐相位打印 `policy` 与 `dockItems`，任一采样点不是 `.accessory` 或 Dock 条目变多即 exit 1。
  `NM_SNIP_DOCK_PROBE=wait` 改为等外部真实按键取消；`=keys` 额外自证方向键真的改了选区。

## 已知限制

- 「Dock 图标是否出现」只能在真实登录会话里验：锁屏 / 无头环境没有 WindowServer，也读不到 Dock AX。
  发版前请用打包后的 .app 跑一次探针，不要用裸二进制（会崩在 UserNotifications）。
- Dock 的 AX 条目有几十毫秒的滞后：探针按 20–50ms 轮询足够抓到几百毫秒以上的泄漏，
  但抓不到只存在一两帧的极端情况。

## 参考文件

- `NetworkMonitor/Sources/NetworkMonitor/Snip/SnipForegroundPolicy.swift`
- `NetworkMonitor/Sources/NetworkMonitorUI/SnipActivationPolicy.swift`（审计判据，可单测）
- `NetworkMonitor/Sources/NetworkMonitor/Debug/SnipDockProbe.swift`（`NM_SNIP_DOCK_PROBE`）
- `NetworkMonitor/Sources/TestRunner/SnipDockIconPolicyTests.swift`（运行期判据 + 源码守卫）
- `NetworkMonitor/Sources/NetworkMonitor/Snip/SnipOverlayWindow.swift`
- `NetworkMonitor/Sources/NetworkMonitor/Snip/SnipController+Overlay.swift`
