# 实现审查 r1（feat/ui-redesign，2026-10-17）

- 分支 `feat/ui-redesign`（HEAD `d439d6a`），合并 `feat/menubar-panel` + `feat/clipboard-redesign`
- 方式：静态核查（规范逐条 grep + 关键文件行号）+ 部署物 strings；**无 P0**
- 时间受限说明：TestRunner 独立复跑**未成功**（见「未覆盖」），测试绿旗沿用 lead 报数
- 结论：**可交用户实测（是）**；P0=0 · P1=3 · P2=4

## 1. 编码规范硬门槛

| 规范条 | 命令 | 结果 |
|---|---|---|
| 禁止 print（ConsoleLogger 外） | `grep -rln "print(" Sources --include=*.swift` | 仅 `TestRunner/main.swift`、`Core/Infrastructure/Logging/Loggers.swift`（ConsoleLogger 内部）→ **合规** |
| 禁止直读 UserDefaults.standard | `grep -rn "UserDefaults.standard" Sources` | **2 处违规**：`Clipboard/ClipboardSettingsWindow.swift:206`、`:328`；`git blame` 均为 `40f8c01`（2026-10-12，早于本分支）→ 存量违规，见 P1-2 |
| Core 不得 import AppKit | `grep -rn "import AppKit" Sources/NetworkMonitorCore \| wc -l` | `0` → 合规 |
| 组合根唯一 / 构造器注入 | 读 `AppCoordinator.swift:115` 等 | AppCoordinator 装配，MenuBarManager/MenuPanelController 均构造器注入 → 合规（具体类型注入见 P2-1） |
| 单文件 >500 行 / >15 KiB | `wc -l` + `stat -f%z` | 新增 `MenuPanel/*` 全部合格（最大 `MenuPanelComponents.swift` 14,978 B < 15,360）；超标仅存量：`TestRunner/main.swift` 849 行 / 46,756 B、`Core/DatabaseManager.swift` 435 行 / 17,585 B → P2-2 |

## 2. 删除完整性

```bash
grep -rniE "token|reasonix|hook|AI 分析|会话统计" Sources --include=*.swift | grep -v Clipboard
# 命中全部落在 Core/DatabaseManager.swift 的「历史表保留」注释与 DDL（hook_events / hook_sessions /
# hook_tool_calls / token_usage），注释明确「代码已不再使用，建表保留仅为兼容既有用户数据」
grep -rnE "TokenUsageRepository|HookEventRepository|ReasonixHookMonitor|HookEventDispatcher" Sources
# 0 命中（已删协议无残留引用）
```
- `MenuBarManager.swift` 现 102 行，无 AI/Token 属性；`onOpenClipboardHistory/Settings` 闭包已由 `MenuPanelController:248/253` 与 `MenuBarManager:46/47` 实际接线（非死代码）。
- **`Package.swift:11,21` 仍声明 `Charts`/`DGCharts`，但 `grep -rn "import DGCharts\|import Charts" Sources` = 0** → 死依赖，见 P1-1。

## 3. 实现保真（代码值 ↔ 原型值）

| 规格 | 原型 | 实现位置与值 | 结论 |
|---|---|---|---|
| 菜单面板宽 | 320 | `MenuPanelComponents.swift:12` `panelWidth = 320` | ✅ |
| 高度 clamp | ≤600 | `:16` `maxHeight = 520`，`MenuPanelController.swift:222-225` `min(max(needed,180),520)` | ✅（风险见 P1-3） |
| 速率大数字 | 26pt | `MenuPanelComponents.swift:31` `heroFont 26 semibold`；`NetworkPaneView.swift:96` 下行 sparkline / `:111` 上行 | ✅ |
| 今日流量双轨 | 80/20 + 轨道 | `NetworkPaneView.swift:145-147` 双行；`:216-221` `MenuPanelMetrics.downShare` 派生占比 | ✅ |
| 进程 5 行 + 真实图标降级 | 20pt 图标 | `NetworkPaneView.swift:240` `limit: 5`；`:287-288` `AppIconProvider.icon(forProcess:) ?? placeholderIcon`、20×20 | ✅ |
| 近 6 日柱 + 今天高亮 | accent | `MenuPanelController` 取 `MenuPanelMetrics.recentDays`；`MenuPanelCharts.swift:79/90/96` `bar.isToday ? accentColor` | ✅ |
| 剪贴板卡片 | 176×198 / 圆角 12 / padding 10 | `ClipboardCardView.swift:16/18/20` | ✅ |
| 卡片字号 | 正文 13 / 等宽 12 / meta 11 | `ClipboardCardView.swift:22/24/26` | ✅ |
| 无 App 名、无 ×N | — | `ClipboardCardView.swift:216` 只画 12pt App 图标；全文件无 App 名/次数绘制 | ✅ |
| meta 单行 + 内容垂直居中 | — | `ClipboardCardView.swift:188-227` 单行 meta；`:158` `(body.height - drawHeight)/2` | ✅ |
| 剪贴板面板 | 640×260 | `ClipboardPanelController.swift:38` `NSRect(0,0,640,260)` | ✅ |
| 工具条/提示行/padding | 32 / 24 / 10 | `ClipboardPanelView.swift:90-93` | ✅ |
| 断行（URL 只在断点换行） | `word-break:normal` | `ClipboardCardTextStyle.swift` `breakable()` 埋零宽空格 + `.byWordWrapping`（`:140`） | ✅ 与原型同策 |
| 快照对照 | 320×498 / 282 / 196、640×260 | `/tmp/nm-shots2/*.png` 实测 `sips` 尺寸逐一吻合 | ✅ |

## 4. 风险复核

- **popover 高度 clamp 520**：网络页快照 498 < 520，当前不裁；但 `MenuPanelView.swift` 内 `grep NSScrollView` = 0 → 内容一旦超 520 会被裁且不可滚动 → P1-3（条件性，当前未触发）。
- **粘贴落点**：`ClipboardPaster.swift:165-190` `recordTargetApplication()` 在面板成为 key 前同步取 frontmost，回退 `preferences.lastExternalBundleID`；`:195-224` 无目标时降级 `copiedOnly("未识别到目标应用…")`；`:242-257` 合成 ⌘V 的 CGEvent（自激标记防回环）。路径完整，**权限分支未实测**（见未覆盖）。
- **MenuBarManager 死代码**：102 行，仅 `timer` 一个可变属性，无残留 → ✅

## 5. 测试覆盖

- `MenuPanelMetrics` 测试齐全：`TestRunner/main.swift:782-844` 覆盖 `recentDays`（正序/今天标记/limit≤0/空）、`downShare`（80%、单边、总量 0）、`barRatios`、`speedParts`（B/KB/MB/GB/负数/0）、`topProcesses`（过滤零流量/limit）→ ✅ 取数口径有覆盖。
- 被删功能的测试：`grep -nE "Token|AI|Hook|token|hook" TestRunner/main.swift` = 0 → 无无主测试 ✅。

## 6. 部署物

```bash
strings /Applications/NetworkMonitor.app/Contents/MacOS/NetworkMonitor | grep -c "NM_SNAPSHOT_DIR"   # 0
strings … | grep -c "MenuPanelSnapshot"                                                             # 0
```
release 产物不含 DEBUG 快照钩子 ✅；`AppDelegate.swift:15-18` 有 `#if DEBUG` 围栏。

## 7. 问题清单

### P0
无（未发现崩溃/功能不可用/规范硬违反中的「新引入」项；门禁数值见未覆盖）。

### P1（应修）
1. **死依赖 `Charts`/`DGCharts`**：`NetworkMonitor/Package.swift:11`（package 声明）、`:21`（product 依赖），`grep -rn "import DGCharts\|import Charts" Sources` = 0。修法：删两处声明（构建时间与供应链面）。
2. **直读 `UserDefaults.standard`（规范第 5 条硬违反，存量）**：`Clipboard/ClipboardSettingsWindow.swift:206`（读 launchAtStartup）、`:328`（写）。`git blame` 均 `40f8c01`（2026-10-12），非本分支引入；本次改动了该文件（视觉重做）时未顺带治理。修法：走注入 `KeyValueStorage`。
3. **popover 520 裁剪无兜底**：`MenuPanelStyle.maxHeight = 520`（`MenuPanelComponents.swift:16`）+ `MenuPanelController.swift:222-225` 直接截断，面板内无 `NSScrollView`。当前网络页 498 未触发，但 520 是硬截断而非滚动 → 建议超限时启用滚动或按页设置上限。复现：构造需高 >520 的内容（如超长进程名/更多行）即可。

### P2（待办）
1. `ClipboardPaster` 以具体类型注入 UI（`MenuPanelController.swift:44,74`、`MenuBarManager.swift:31`、`ClipboardPanelController.swift:15`），无协议抽象（DIP 轻微偏离）。
2. 存量超限文件：`TestRunner/main.swift` 849 行 / 46,756 B（>500 行 & >15 KiB）、`Core/DatabaseManager.swift` 435 行 / 17,585 B（>15 KiB）。
3. `DatabaseManager.swift` 仍建 `token_usage` 等历史表（`:271-351`，注释声明仅兼容旧数据）；建议加「停建 + 只读迁移」计划。
4. `/tmp/nm-shots2/` 为临时目录，快照属取证材料，建议归档到 `.open-design/impl-notes/`（当前 `/tmp` 会被清理）。

## 8. 未覆盖 / 待查（不继续深挖）

- **TestRunner 未独立复现**：`swift run --disable-sandbox TestRunner` 首次报 `Could not initialize build system … Unknown error parsing property list`；二次重试因本机无 `timeout` 命令未真正执行。「🎉 所有测试通过」沿用 lead 报数，未独立验证。
- 粘贴链路的辅助功能权限分支（`ClipboardPaster` 权限不足时的降级）未实测。
- 面板真实渲染（vibrancy/圆角/焦点）只核了快照尺寸，未逐像素与原型比对。

## 9. 结论

**可交用户实测（是）**：P0=0；规范硬门槛除「存量 UserDefaults 直读」外全部通过；实现规格与原型数值逐项吻合；release 已剔除 DEBUG 钩子；删除完整性无残留协议引用。建议并行处理 P1-1（删死依赖）与 P1-2（UserDefaults 注入），P1-3 观察是否在实际内容下触发。
