# UI 设计规范

> ⚠️ **何时阅读：** 当你需要开发或修改 UI 代码（菜单栏、下拉菜单、图表）时，必须先阅读本文档。

## 设计原则

1. **简洁克制** — 菜单栏空间有限，只展示最重要的信息（网络速度）
2. **一目了然** — 用户只需扫一眼就能知道当前网络状态
3. **交互直观** — 单击展开菜单，点击操作项执行动作
4. **信息层级清晰** — 网速 > 流量 > Token 统计 > 操作

## 设计语言（Design Tokens）

### 颜色

统一使用 `NSColor` 系统颜色，保证深浅色模式自适应：

| 用途 | 系统色 | 说明 |
|------|--------|------|
| 下行速度（下载） | `systemGreen` | 菜单栏 + 菜单 |
| 上行速度（上传） | `systemOrange` | 菜单栏 + 菜单 |
| 标题/强调 | `labelColor` | 主文本 |
| 次要信息 | `secondaryLabelColor` | 辅助文本、图标 |
| 图表柱 | `systemBlue.withAlphaComponent(0.7)` | Token 柱状图 |

### 字体

| 用途 | 字体 | 说明 |
|------|------|------|
| 菜单栏数字 | `monospacedDigitSystemFont(10, .regular)` | 等宽数字防抖动 |
| 菜单标题 | `monospacedDigitSystemFont(12, .medium)` | 今日流量标题 |
| 图表 X 轴 | `systemFont(8)` | 小时/日期标签 |
| 图表数值 | `monospacedDigitSystemFont(7, .regular)` | 柱顶数值 |

### 图标

所有图标使用 **SF Symbols**（`NSImage(systemSymbolName:)`），设置 `isTemplate = true`：

| 用途 | Symbol | 说明 |
|------|--------|------|
| 网络 | `network` | IP 行 |
| 进程 | `app.connected.to.app.below.fill` | 活跃进程 |
| 流量汇总 | `arrow.down.arrow.up` | 二级菜单 |
| Token | `chart.bar.fill` | Token 一级概览 |
| 历史用量 | `calendar.badge.clock` | 二级菜单 |
| AI 分析 | `brain.head.profile` | 二级菜单 |
| AI 实时动态 | `antenna.radiowaves.left.and.right` | 子菜单 |
| AI 工具统计 | `wrench.adjustable` | 子菜单 |
| AI 模型统计 | `cpu` | 子菜单 |
| AI 项目统计 | `folder` | 子菜单 |
| AI 会话统计 | `chart.pie` | 子菜单 |
| 启动项 | `clock.arrow.circlepath` | 开机自启 |
| 退出 | `power` | 退出 |
| 趋势/图表 | `chart.line.uptrend.xyaxis` | 通用 |

## 菜单栏设计规范（StatusBarView）

只显示网络速度（下行 + 上行），**不显示其他信息**：

```
┌──────────────────────────────────┐
│  ↑ 1.2M    ↓ 340K               │  ← 单行紧凑布局
└──────────────────────────────────┘
```

- 上行（橙）在前，下行（绿）在后，格式：`↑1.2M  ↓340K`
- 使用 `attributedTitle`（NSAttributedString）替代自定义 NSView，降低 CPU 占用
- 背景透明，跟随系统菜单栏

## 下拉菜单设计规范（NSMenu）

### 整体结构

```
┌─ 网络监控  ↓12.5GB  ↑3.2GB  ──┐
│ ───────────────────────────── │ ← separator
│  ◉ 192.168.1.100              │ ← IP
│ ───────────────────────────── │
│  活跃进程 ▶                   │ ← 二级菜单（Top 10 进程）
│  流量汇总 ▶                   │ ← 二级菜单（今日 + 近7日明细）
│ ───────────────────────────── │
│  Token: 12.3万 | 花费: ¥8.88  │ ← Token 一级概览
│  [24小时柱状图]               │ ← 内嵌 BarChartView（260×80）
│  历史用量 ▶                   │ ← 二级菜单（7日柱状图 260×100）
│  AI 分析 ▶                    │ ← 二级菜单（5 个子菜单）
│ ───────────────────────────── │
│  🔄 开机自启                   │ ← 开关状态（✓/空白）
│  ⏻ 退出                ⌘Q     │
└───────────────────────────────┘
```

> 注：ASCII 图中使用近似符号示意，实际代码中全部使用 SF Symbols。

### 菜单项规范

| 元素 | 交互 |
|------|------|
| 菜单栏图标 | 单击展开菜单 |
| 信息项（IP/进程/统计） | `isEnabled = false`，仅展示 |
| 开机自启 | 点击切换开关状态（`state = .on/.off`） |
| 退出 | 点击退出应用（`⌘Q`） |

### 刷新策略

- 网速每秒更新；流量区每 5 秒；Token/AI 统计每 15 秒（SQLite 查询）
- 菜单打开时（`menuWillOpen`）强制刷新全部统计
- 图表仅在数据 hash 变化时重建，避免无谓动画

## Token 图表规范（TokenChartView）

内嵌菜单的迷你柱状图（DGCharts `BarChartView`）：

| 参数 | 一级（24小时） | 二级（7日） |
|------|--------------|------------|
| 尺寸 | 260 × 80 | 260 × 100 |
| 柱宽 | 0.7 | 0.6 |
| X 轴标签 | 小时数（最多 7 个） | 日期 M/d |
| 数值标签 | 0 不显示；≥1 万显示"X万"；≥1 亿显示"X亿" | 同左 |
| 动画 | `animate(0.3s)` 仅数据变化时 | 同左 |

样式：无网格线、无图例、`backgroundColor = .clear`、柱色 `systemBlue 70%` 透明度。

## 代码结构规范

UI 类按功能拆分到独立文件：

| 文件 | 类/内容 | 说明 |
|------|---------|------|
| `StatusBarView.swift` | `StatusBarView` | 菜单栏属性字符串生成 |
| `TokenChartView.swift` | `MiniMenuChartView` / `MiniHistoryMenuChartView` | Token 柱状图 |
| `MenuBarManager.swift` | `MenuBarManager` | UI 总控制器 + NSMenu 构建 + 分层刷新 |
| `AppCoordinator.swift` | `AppCoordinator` | 服务生命周期 + 依赖注入 |
| `AppDelegate.swift` | `AppDelegate` | 应用入口 |

## 检查清单

开发 UI 前/后，请对照以下清单检查：

- [ ] 是否先做了设计草图/原型？
- [ ] **是否使用 SF Symbols 替代了所有 emoji？**
- [ ] 颜色是否使用了 `NSColor` 系统颜色？
- [ ] 字体是否使用了系统字体（`systemFont` / `monospacedDigitSystemFont`）？
- [ ] 间距是否符合 4pt 基准体系？
- [ ] 是否适配了深色/浅色模式？
- [ ] 信息层级是否合理？
- [ ] 菜单是否在数据变化时才重建（避免每秒重建）？
- [ ] 代码是否按功能拆分到独立文件？

## 修订历史

| 日期 | 版本 | 修改说明 |
|------|------|----------|
| 2025-06-29 | 1.0 | 初始版本，建立设计先行的规范和设计系统 |
| 2026-06-30 | 2.0 | 全面 UI 重设计：macOS 15 现代风格，emoji→SF Symbols，菜单栏仅网速，面板毛玻璃效果，卡片分区布局，代码结构拆分 |
| 2026-08-03 | 2.1 | 同步当前实现：移除已删除的电池/本机监控/详情面板章节，新增 Token 图表规范与分层刷新策略 |
