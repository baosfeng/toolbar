# Token tab 分屏改造 · 设计规格

> 何时阅读：调整 Token 页信息架构 / 新增 Token 屏时。

## 问题

主面板把 8 个区块塞在一屏（Hero → 四族卡 2×2 → 24h 主图 → 缓存环 → 项目/模型双栏 → 14 天趋势 → 今日 vs 昨日 → 状态带），520pt 内要么看不到图表、要么看不到分布。用户要求「分屏 + 二级菜单页」，且图表美观清晰、数据清晰完整。

## 结构：4 屏 + 3 个二级页

页头（主机 + 范围分段 + 刷新）→ **屏切换条（概览 / 用量 / 缓存 / 排行）** → 屏内容（可滚动）+ **屏页脚**（钉在屏底）。

| 屏 | 内容（自顶向下） | 页脚 | 数据口径 |
|---|---|---|---|
| **概览** | Hero（范围总量 + 较昨日 + 实时）、四族卡 2×2（含 sparkline 与占比）、**缓存命中紧凑条**（小环 30pt + 命中率大字 + 缓存读 / 未缓存 / 节省比例，整条可点进缓存屏）、**近 14 天迷你走势（56pt）**、**今日 vs 昨日同期** | 状态带 | 跟随范围（缓存条取 cachePage） |
| **用量** | 24h 主图（**160pt**，左侧刻度 + 4 条网格虚线，今日/昨日、堆叠/对比、切请求数、累计虚线、每柱可点）、14 天天趋势（**120pt**） | 状态带 | 跟随范围 |
| **缓存** | 大命中环（72pt）+ 四行拆分、命中率趋势（空缺桶断开）、本周期 vs 上一周期、样本统计 | 口径说明 | 跟随范围（Core 的 cachePage） |
| **排行** | 维度分段（项目 / 模型）、占比条 + **Top 8 两行式行**（行 1 = 色点 + 名称 + tok + 占比；行 2 = 会话数 · 请求数；行底 = 行内微占比条）、计数统计 | 状态带 | 跟随范围（Core 的 distroCopy） |

**固定高度（第二轮）**：四屏 pane 高度一律 458pt（屏外框 409 + 页头与屏切换条 49），desiredContentHeight 恰好 520 = popover 上限 → 切屏不跳高跳低；内容超出外框时走**屏内**滚动，页脚固定屏底不动；切屏后滚动归顶。页脚：概览 / 用量 / 排行 = 状态带（每屏一个实例、同一份 model.stateBand），缓存 = 口径说明。

**空缺口径（第二轮）**：`cachePage.series` 为 `[Double?]`，分母为 0 的桶（无会话的小时 / 天）= `nil`（长度不变，横轴对齐）；走势图遇 `nil` **断开**——不连线、不落底、面积不填到 0，孤立数据点画 2.8pt 圆点；卡头纵轴写真实 min–max（如「纵轴 97.4% – 98.9%」），整窗无数据写「无有效桶 · N 桶」，不再出现「0.0% – 98.7%」。

二级页（覆盖式，保留）：**单桶详情**（点柱子，小时桶 / 日桶）、**按小时三段拆分**（用量屏「24h 明细 ›」）、**天趋势明细**（用量屏「30 天 ›」）。
原 `.cache` / `.projects` / `.models` 三个二级页并入对应屏，入口删除，不留死代码。

## 控件

- 屏切换：`TokenSegmentedControl`，标题 概览 / 用量 / 缓存 / 排行；四段等宽（`expands: true`），与范围分段同族但更轻（第二行）。
- 键盘：`focusableRows` 按当前屏给（屏切换条 + 屏内卡片可聚焦；页脚不参与焦点）。
- 屏切换流程：切显隐 → 屏内滚动归顶 → render → `onContentChanged`（高度已恒定，通知保留用于 popover 尺寸同步）。
- 排行行：`TokenRankingRowView`（两行式 + 行内微占比条 + 色点 + tooltip）；卡片高度 = 外框 − 页脚 = 385pt，可见行用 `fillEqually` 均分 → 4 行时行距舒展、8 行时收紧也不压行（行最小高 34pt）。改前的单行截断式与三项图例都已删除。
- 主图刻度：左栏宽 34pt，值 = 归一化基准 × 比例（0 / 中值 / 峰值），用 `TokenFormatting.abbreviated` 化简（跟随设置页「数值单位」），横轴刻度行按同一宽度右移对齐；网格为 4 条水平虚线（25 % / 50 % / 75 % / 100 %），刻度栏内点击不算选列。

## 代码落点

| 层 | 文件 | 改动 |
|---|---|---|
| UI 纯逻辑（可测） | `NetworkMonitorUI/Token/TokenScreen.swift`（新） | `enum TokenScreen`（overview/usage/cache/ranking）+ title + `TokenScreenBlock` 分区契约（每个区块归属唯一屏） |
| 视图 | `MenuPanel/TokenPaneView.swift` | 新增 `screen` 状态、`screenControl`、屏容器；DEBUG `selectScreenForSnapshot` |
| 视图 | `MenuPanel/TokenScreenFrameView.swift`（新） | 屏外框：固定高度 + 内容滚动区 + 页脚 |
| 视图 | `MenuPanel/TokenPaneView+Layout.swift` | 4 个屏外框装配（内容按契约、页脚按 `TokenScreen.footer`） |
| 视图 | `MenuPanel/TokenPaneView+Render.swift` | 更新全部屏控件；按 `screen` 切显隐 |
| 视图 | `MenuPanel/TokenScreenContent.swift`（新） | 缓存屏内容构建 + 共用卡片组件（从 `TokenDetailPages+Distro.swift` 抽出，二级页与屏共用） |
| 视图 | `MenuPanel/TokenCacheHitStrip.swift`（新） | 概览屏「缓存命中」紧凑条（数据取 `cachePage`） |
| 视图 | `MenuPanel/TokenRankingRowView.swift`（新） | 排行屏两行式行（色点 / 名称 / tok / 占比 / 会话数 · 请求数 / 微占比条） |
| 视图 | `MenuPanel/TokenDetailPages.swift` | `TokenDetailKind` 收成 bucket / hourly / trend |
| 快照 | `Debug/TokenPaneSnapshot*.swift` | 补 4 屏 × 浅深取证 |

## 硬约束

- 数据口径一个都不改：所有数值仍来自 `TokenPaneModel`（Core 派生），视图只搬运。
- 文件 ≤500 行 / ≤15 KiB，超了按「主类 + 扩展文件」拆。
- 新增纯逻辑必须配 TestRunner 断言（`TokenScreen` 的标题 / 顺序 / 区块归属唯一性 / 每屏页脚）。
- 空缺口径由 Core 表达（`series: [Double?]`），视图不得把 `nil` 当 0 画。
- 编译 `swift build --disable-sandbox --build-system native`、测试 `swift run … TestRunner` 全绿、`bash NetworkMonitor/Scripts/check-file-size.sh` 通过。

## 验收

1. 4 屏各自截图（浅/深）可读：概览填到接近页脚、用量图高 ≥160pt 且带左侧刻度与网格、缓存屏不滚动即可看全（环 + 三块 + 页脚口径）、排行卡片撑到页脚上方且行前色点与占比条同色。
1b. 台账给出「内容占可视区比例 / 剩余空白」：概览 ≥90 %、用量 ≥95 %、排行 = 100 %（卡片撑满）；缓存允许 ≥95 %。
2. **四屏 pane 高度一致**（台账 `pane 高度一致 = YES`），无 Auto Layout 冲突；切屏滚动归顶。
3. 缓存屏 24 桶有空缺时：折线在缺口断开、纵轴写真实 min–max，不出现「0.0%」起点。
4. 同一范围下，四屏数字与旧版对应区块一致（抽查 hero 总量、缓存命中率、项目 Top1）。
5. 屏切换后键盘焦点不丢失、Esc 在二级页返回。
6. 快照命令：`NM_SNAPSHOT_DIR=/tmp/nm-shots <包内可执行文件>`，产出 4 屏 × 2 外观 + `menu-token-screens.txt` 台账。