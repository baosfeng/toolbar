---
name: toolbar-ui-standards
description: 本项目 UI 设计规范：Design Tokens（系统色/字体/SF Symbols）、菜单栏/下拉菜单/图表规范，写 UI 代码前必加载
---

# UI 设计规范（NetworkMonitor / macMonitor）

本项目 UI（菜单栏、下拉菜单、Token 图表）专属设计规范。**开发或修改任何 UI 代码前必须加载本 skill。** 由 `docs/开发指南/UI设计规范.md` 迁入（2026-08 文档瘦身），后续 UI 规范更新一律写在本 skill。

## 设计原则

1. **简洁克制** — 菜单栏空间有限，只展示最重要的信息（网速）
2. **一目了然** — 扫一眼即知当前状态；**信息层级**：网速 > 流量 > Token 统计 > 操作
3. **交互直观** — 单击展开菜单，点击操作项执行动作

## Design Tokens

### 颜色（统一 `NSColor` 系统色，深浅色自适应）

| 用途 | 系统色 |
|------|--------|
| 下行速度 | `systemGreen` |
| 上行速度 | `systemOrange` |
| 标题/强调 | `labelColor` |
| 次要信息 | `secondaryLabelColor` |
| 图表柱 | `systemBlue.withAlphaComponent(0.7)` |

### 字体

| 用途 | 字体 |
|------|------|
| 菜单栏数字 | `monospacedDigitSystemFont(10, .regular)`（等宽防抖动） |
| 菜单标题 | `monospacedDigitSystemFont(12, .medium)` |
| 图表 X 轴 | `systemFont(8)` |
| 图表数值 | `monospacedDigitSystemFont(7, .regular)` |

### 图标

全部使用 **SF Symbols**（`NSImage(systemSymbolName:)` + `isTemplate = true`），**禁止 emoji 图标**：
网络 `network` / 进程 `app.connected.to.app.below.fill` / 流量 `arrow.down.arrow.up` / Token `chart.bar.fill` / 历史 `calendar.badge.clock` / AI `brain.head.profile` / 实时动态 `antenna.radiowaves.left.and.right` / 工具统计 `wrench.adjustable` / 模型 `cpu` / 项目 `folder` / 会话 `chart.pie` / 自启 `clock.arrow.circlepath` / 退出 `power`

## 菜单栏（StatusBarView）

- 只显示网速：上行（橙）在前、下行（绿）在后，`↑1.2M  ↓340K` 单行紧凑
- 使用 `attributedTitle`（NSAttributedString）替代自定义 NSView，降低 CPU 占用
- 背景透明，跟随系统菜单栏

## 下拉菜单（NSMenu）

结构：标题（今日流量）→ IP → 活跃进程 ▶ → 流量汇总 ▶ → Token 概览 + 24h 柱状图 → 历史用量 ▶ → AI 分析 ▶ → 开机自启 → 退出（⌘Q）

- 信息项（IP/进程/统计）`isEnabled = false` 仅展示；自启点击切换 `state = .on/.off`
- 刷新：网速 1s / 流量 5s / Token·AI 15s；`menuWillOpen` 强制全刷新
- 图表仅在数据 hash 变化时重建，避免无谓动画

## Token 图表（TokenChartView，DGCharts BarChartView）

| 参数 | 一级（24 小时） | 二级（7 日） |
|------|--------------|------------|
| 尺寸 | 260 × 80 | 260 × 100 |
| 柱宽 | 0.7 | 0.6 |
| X 轴 | 小时数（≤7 标签） | 日期 M/d |
| 数值 | 0 不显示；≥1 万"X万"；≥1 亿"X亿" | 同左 |

样式：无网格线、无图例、`backgroundColor = .clear`、柱色 `systemBlue` 70% 透明度、`animate(0.3s)` 仅数据变化时。

## 代码结构

| 文件 | 内容 |
|------|------|
| `StatusBarView.swift` | 菜单栏属性字符串生成 |
| `TokenChartView.swift` | `MiniMenuChartView` / `MiniHistoryMenuChartView` |
| `MenuBarManager.swift` | UI 总控制器 + NSMenu 构建 + 分层刷新 |
| `AppCoordinator.swift` | 服务生命周期 + 依赖注入（组合根） |

## 检查清单

- [ ] 使用 SF Symbols 而非 emoji 图标？
- [ ] 颜色/字体均为系统 API？
- [ ] 适配深/浅色模式？
- [ ] 菜单仅数据变化时重建？
- [ ] 布局遵循 4pt 基准、信息层级合理？
