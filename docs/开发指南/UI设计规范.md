# UI 设计规范

> ⚠️ **何时阅读：** 在开发任何新功能或修改现有 UI 之前，**必须先阅读本文档**。本文档规定了「先设计、后开发」的工作流程和 UI 设计标准。

## 核心理念：先设计，后开发

### 原则

1. **设计先行** — 在写任何 UI 代码之前，先用设计稿确定布局、颜色、字体、图标与交互
2. **系统原生优先** — 优先使用系统原生的 SF Symbols 图标集和系统颜色（`NSColor`），保持 macOS 平台一致性
3. **一致的设计语言** — 所有界面共享同一套色彩、间距、字体层级
4. **少即是多** — 信息展示要克制，避免信息过载；用视觉层级引导用户注意力

### 工作流程

```
需求分析 → 设计草图 → 设计确认 → 编码实现 → UI 走查
```

| 阶段 | 输出 | 说明 |
|------|------|------|
| 需求分析 | 功能列表 + 用户故事 | 明确要做什么、给谁用 |
| 设计草图 | ASCII 设计稿 / 手绘稿 | 确定布局、交互流程 |
| 设计确认 | 在自审中确认设计合理 | 确保一致性和可用性 |
| 编码实现 | 符合本规范的 Swift 代码 | 使用系统组件 + SF Symbols |
| UI 走查 | 截图对比 + 像素级检查 | 检查间距、颜色、对齐 |

## 设计系统

### macOS 15+ 现代风格指南

本项目视觉风格基于 **macOS 15 Sequoia 设计语言**：
- **毛玻璃效果** — 详情面板使用 `NSVisualEffectView`（`.popover` 材质）
- **圆角卡片** — 所有容器使用 8pt 圆角 + 系统填充色
- **系统字体** — SF Pro（`systemFont`），数字使用 `monospacedDigitSystemFont`
- **单色图标** — SF Symbols 主色调统一，功能性颜色（绿/橙/蓝）仅用于区分下载/上传/IP
- **宽松间距** — 面板边缘 16pt，分组间距 12pt，元素间距 8pt

### 🎨 色彩系统

| 用途 | 颜色 | SF Symbol 色 | 说明 |
|------|------|-------------|------|
| 主色（品牌） | `systemBlue` | 蓝色图标 | IP/Wi-Fi 信息 |
| 下载速度 | `systemGreen` | 绿色图标 | 下行流量 |
| 上传速度 | `systemOrange` | 橙色图标 | 上行流量 |
| 警告/错误 | `systemRed` | 红色图标 | 低电量/异常 |
| 次要文本 | `secondaryLabelColor` | — | 辅助说明 |
| 面板背景 | `NSVisualEffectView` | — | 毛玻璃材质 |
| 卡片背景 | `controlBackgroundColor` | — | 系统控制背景色 |
| 分割线 | `separatorColor` | — | 细线分隔 |

> 始终使用 `NSColor` 的系统命名颜色，确保自动适配深色/浅色模式。

### 🔤 字体层级

| 层级 | 字体 | 大小 | 字重 | 用途 |
|------|------|------|------|------|
| 超大数字 | `monospacedDigitSystemFont` | 28 | `.bold` | 详情面板速度数值 |
| 大数字 | `monospacedDigitSystemFont` | 20 | `.bold` | 菜单内速度显示 |
| 标题 | `systemFont` | 13 | `.semibold` | 分区标题 |
| 正文 | `systemFont` | 12 | `.regular` | 标签、描述文本 |
| 辅助 | `systemFont` | 11 | `.regular` | 进程列表、小字信息 |
| 菜单栏 | `monospacedDigitSystemFont` | 10 | `.regular` | 菜单栏速度数字 |

### 📐 间距系统

使用 4 为基准的间距系统：

| Token | 值 | 用途 |
|-------|-----|------|
| `spacing(1)` | 4pt | 紧凑间距 / 图标与文字 |
| `spacing(2)` | 8pt | 默认间距 / 同一组元素 |
| `spacing(3)` | 12pt | 分组间距 / 分区之间 |
| `spacing(4)` | 16pt | 面板边距 / 卡片内边距 |
| `spacing(5)` | 20pt | 大间距 |
| `spacing(6)` | 24pt | 段落间距 / 分区上下 |

### 🎯 图标系统（SF Symbols）

**所有图标必须使用 SF Symbols**（macOS 内置），**禁止使用 emoji**。

| 用途 | SF Symbol 名称 | 颜色 | 替代旧 emoji |
|------|---------------|------|-------------|
| 下载 | `arrow.down.circle.fill` | `systemGreen` | — |
| 上传 | `arrow.up.circle.fill` | `systemOrange` | — |
| Wi-Fi | `wifi` | `systemBlue` | 📶 |
| IP 地址 | `network` | `systemBlue` | 🌐 |
| 电池 | `battery.100` | `labelColor` | 🔋 |
| 充电中 | `bolt.fill` | `systemYellow` | ⚡ |
| 循环次数 | `arrow.counterclockwise` | `secondaryLabelColor` | 🔄 |
| 健康度 | `heart.fill` | `systemRed` | ❤️ |
| 进程/应用 | `app.connected.to.app.below.fill` | `secondaryLabelColor` | — |
| 详情面板 | `info.circle.fill` | `systemBlue` | — |
| 复制 | `doc.on.doc` | — | — |
| 导出 | `square.and.arrow.up` | — | — |
| 退出 | `power` | — | — |
| 设置 | `gear` | — | — |
| 趋势/图表 | `chart.line.uptrend.xyaxis` | `secondaryLabelColor` | 📈 |
| 总计 | `arrow.down.arrow.up` | `secondaryLabelColor` | ↕ |
| 启动项 | `clock.arrow.circlepath` | — | 🔄 |
| 活跃时间 | `clock.fill` | `secondaryLabelColor` | ⏱ |
| 击键 | `keyboard.fill` | `secondaryLabelColor` | ⌨️ |
| 亮屏 | `sun.max.fill` | `secondaryLabelColor` | 💡 |
| 息屏 | `moon.fill` | `secondaryLabelColor` | 🌙 |
| CPU | `cpu` | `secondaryLabelColor` | 💻 |
| 内存 | `memorychip` | `secondaryLabelColor` | — |
| 电源 | `powerplug` | `secondaryLabelColor` | ⚡ |
| 网络总计 | `arrow.down.arrow.up` | `secondaryLabelColor` | ↕ |
| 空状态 | `tray.full` | `secondaryLabelColor` | — |

## 菜单栏设计规范

作为菜单栏 App，设计上应遵循以下原则：

1. **简洁克制** — 菜单栏空间有限，只展示最重要的信息（网络速度）
2. **一目了然** — 用户只需扫一眼就能知道当前网络状态
3. **交互直观** — 单击展开菜单，双击打开详情面板
4. **信息层级清晰** — 速度 > 电池 > 进程详情 > 操作

### 菜单栏视图布局（StatusBarView）

只显示网络速度（下行 + 上行），**不显示电池信息**：

```
┌──────────────────────────────────┐
│  ↓ 1.2M/s    ↑ 340K/s           │  ← 单行紧凑布局
└──────────────────────────────────┘
```

- 绿色 `arrow.down.circle.fill` + 下行速度（`systemGreen`）
- 橙色 `arrow.up.circle.fill` + 上行速度（`systemOrange`）
- 使用 `monospacedDigitSystemFont(10, .regular)` 等宽数字
- 背景透明，跟随系统菜单栏

## 下拉菜单设计规范（NSMenu）

### 整体结构

```
┌─ 网络监控  ↓12.5GB  ↑3.2GB  ──┬────────────────────┐
│ ───────────────────────────── │ ← separatorColor   │
│                               │                     │
│  ↓ 1.2 MB/s                   │ ← 下载速度（systemGreen）│
│  ↑ 340 KB/s                   │ ← 上传速度（systemOrange）│
│  ───────────                  │ ← 细分隔线           │
│  ◉ 192.168.1.100              │ ← IP（systemBlue）  │
│  ◉ Wi-Fi: MyNetwork           │ ← Wi-Fi（systemBlue）│
│  ↕ 累计: ↓12.5 GB  ↑3.2 GB  │ ← 总计（secondary） │
│                               │                     │
│ ───────────────────────────── │ ← separatorColor    │
│                               │                     │
│    92%                       │ ← 电池百分比        │
│  ◷ 剩余 2h 10m                │ ← 剩余时间          │
│   交流电  ✓ 已充满           │ ← 电源状态          │
│  綾 循环: 152次   ♥ 健康: 正常 │ ← 循环+健康         │
│                               │                     │
│ ───────────────────────────── │ ← separatorColor    │
│                               │                     │
│  活跃进程                      │ ← 分区标题          │
│  [Chrome icon]  Chrome  ↓1.2M  ↑340K               │
│  [iTerm2 icon]  iTerm2  ↓230K  ↑120K               │
│  ...                          │                     │
│                               │                     │
│ ───────────────────────────── │ ← separatorColor    │
│                               │                     │
│    活跃: 6h32m     击键: 3.8K                    │
│    亮屏: 8h15m     息屏: 2h10m                   │
│    CPU: 6.2%   内存: 8.4/16GB                    │
│                               │                     │
│ ───────────────────────────── │ ← separatorColor    │
│                               │                     │
│  ⓘ 详情面板                   │ ← 带 SF Symbol 的操作项│
│  📋 复制信息                   │                     │
│  ⬆ 导出日志                   │                     │
│  🔄 开机自启                   │                     │
│  ⏻ 退出                      │                     │
└──────────────────────────────────────────────────────┘
```

> 注：ASCII 图中使用近似符号示意，实际代码中全部使用 SF Symbols。

### 交互规范

| 元素 | 交互 |
|------|------|
| 菜单栏图标 | 单击展开菜单，双击打开详情面板 |
| 进程项 | 不可点击，仅展示信息（带应用图标） |
| 详情面板按钮 | 点击打开/关闭详情面板 |
| 复制、导出 | 点击执行对应操作 |
| 开机自启 | 点击切换开关状态 |
| 退出 | 点击退出应用 |

## 详情面板设计规范（DetailPanel）

使用毛玻璃背景 + 卡片分区布局：

```
┌───────────────────────────────────┐
│  网络监控                          │ ← 标题栏
│ ───────────────────────────────── │
│                                   │
│  ┌── 网速 ──────────────────┐    │ ← 卡片容器（圆角 8pt）
│  │  ↓ 1.2 MB/s              │    │ ← 大号绿色数字（28pt bold）
│  │  ↑ 340 KB/s              │    │ ← 大号橙色数字（28pt bold）
│  └──────────────────────────┘    │
│                                   │
│  ┌── 网络信息 ──────────────┐    │
│  │  ◉ 192.168.1.100        │    │ ← SF Symbol + 正文
│  │  ◉ Wi-Fi: MyNetwork     │    │
│  │  ↕  ↓12.5 GB  ↑3.2 GB  │    │
│  └──────────────────────────┘    │
│                                   │
│  ┌── 电池 ──────────────────┐    │
│  │    92%                   │    │ ← 大图标 + 大百分比
│  │  剩余 2h 10m              │    │ ← 次要信息行
│  │  交流电  ✓ 已充满          │    │
│  │  循环: 152次  健康: 正常   │    │
│  └──────────────────────────┘    │
│                                   │
│  ┌── 活跃进程 ──────────────┐    │
│  │  Chrome      ↓1.2M  ↑340K│    │ ← 应用图标 + 名称 + 速度
│  │  iTerm2      ↓230K  ↑120K│    │
│  │  Safari      ↓150K  ↑80K │    │
│  │  ...                     │    │
│  └──────────────────────────┘    │
│                                   │
└───────────────────────────────────┘
```

### 面板参数
- 尺寸：360 × 520pt（自动适应内容高度）
- 材质：`NSVisualEffectView`（`.popover` 材质）
- 圆角：窗口圆角跟随系统，内部卡片 8pt
- 背景色：`controlBackgroundColor`（卡片）

### 卡片样式
- **背景**：`controlBackgroundColor` + `cornerRadius = 8`
- **内边距**：上下 12pt，左右 16pt
- **标题**：`sectionFont`（12pt semibold, `secondaryLabelColor`）
- **间距**：卡片之间 8pt，卡片边缘距面板 16pt

## 代码结构规范

UI 类应按功能拆分到独立文件，避免全部堆在一个文件中：

| 文件 | 类/内容 | 说明 |
|------|---------|------|
| `StatusBarView.swift` | `StatusBarView` | 菜单栏自定义视图 |
| `DetailPanel.swift` | `DetailPanel` | 浮动详情面板 |
| `MenuBarManager.swift` | `MenuBarManager` | UI 总控制器 + NSMenu 构建 |
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
- [ ] 交互是否直观（单击/双击/右键）？
- [ ] 代码是否按功能拆分到独立文件？

## 修订历史

| 日期 | 版本 | 修改说明 |
|------|------|----------|
| 2025-06-29 | 1.0 | 初始版本，建立设计先行的规范和设计系统 |
| 2026-06-30 | 2.0 | 全面 UI 重设计：macOS 15 现代风格，emoji→SF Symbols，菜单栏仅网速，面板毛玻璃效果，卡片分区布局，代码结构拆分 |
