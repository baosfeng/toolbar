# Token tab 分屏改造 · 设计规格

> 何时阅读：调整 Token 页信息架构 / 新增 Token 屏或二级页时。

## 问题

主面板把 8 个区块塞在一屏（Hero → 四族卡 2×2 → 24h 主图 → 缓存环 → 项目/模型双栏 → 14 天趋势 → 今日 vs 昨日 → 状态带），520pt 内要么看不到图表、要么看不到分布。用户要求「分屏 + 二级菜单页」，且图表美观清晰、数据清晰完整。

## 结构：2 屏 + 4 个面板内二级页

页头（来源 + 会话数 + 范围分段 + 刷新）→ **屏切换条（总览 / 分布）** → 屏内容（可滚动）+ **屏页脚**（钉在屏底）。

| 屏 | 内容（自顶向下） | 页脚 | 数据口径 |
|---|---|---|---|
| **总览** | Hero 46pt（范围总量 + 较昨日 + 实时）、四族卡 2×2 122pt（未缓存输入 / 输出 / 缓存读 / 请求数，含 sparkline 与占比）、**缓存命中紧凑条 42pt**（小环 30pt + 命中率大字 + 缓存读 / 未缓存 / 节省比例，整条可点进缓存命中二级页）、**主图 163pt**（柱高 96pt，左侧刻度 + 4 条网格虚线，今日/昨日、堆叠/对比、切请求数，每柱可点进单桶页，卡头「14 天 ›」进天趋势页） | 状态带 | 跟随范围（缓存条取 cachePage） |
| **分布** | **维度分布卡 331pt**（维度分段 = 工具 / 项目 / 模型、占比条 + **Top 8 两行式行**（行 1 = 色点 + 名称 + tok + 占比；行 2 = 会话数 · 请求数；行底 = 行内微占比条）、**汇总块**（总 tok / 缓存读 / 未缓存 / 输出 / 请求数，取该维度合计）、**单行短口径** + 悬停给全文）、**今日 vs 昨日同期 50pt** | 状态带 | 跟随范围（Core 的 distroCopy 与 window totals） |

**区块归属是契约**：屏标题与区块归属的唯一真源是 `NetworkMonitor/Sources/NetworkMonitorUI/Token/TokenScreen.swift`——`TokenScreen` 只有 `overview` / `distro` 两个 case、标题「总览 / 分布」（该文件 20–33 行），`TokenScreenBlock` 的归属是 hero / familyCards / cacheHit / hourChart → 总览、distro / compare → 分布（83–88 行），页脚两屏都是状态带（38–39 行）。归属写错在截图里很难看出来（同一块画两遍 / 某块哪屏都不显示），所以归属做成纯逻辑，`NetworkMonitor/Sources/TestRunner/TokenScreenTests.swift`（21–44 行）直接断言「每个区块恰好一个屏、两屏合起来覆盖全部区块」。

**固定高度**：两屏 pane 高度一律 458pt（屏外框 409 + 页头与屏切换条 49），desiredContentHeight 恰好 520 = popover 上限 → 切屏不跳高跳低。三处落点：

- 屏外框 `TokenPaneView.screenHeight = 409`（`NetworkMonitor/Sources/NetworkMonitor/MenuPanel/TokenPaneView.swift` 157 行，155–156 行列了减法链）；
- 内容预算 = 409 − 状态带 20 − 间距 4 = **385pt**（同文件 160 行）；
- 两屏都用到最后一 pt：总览 46 + 122 + 42 + 163 + 3×4 = 385，分布 331 + 50 + 4 = 385。各块高度来源：Hero 46（`NetworkMonitor/Sources/NetworkMonitorDesign/PaneCardStyle.swift` 110 行）、四族卡 2×59 + 间距 4 = 122（`NetworkMonitor/Sources/NetworkMonitor/MenuPanel/TokenPaneStyle.swift` 105 行）、缓存条 42（`NetworkMonitor/Sources/NetworkMonitor/MenuPanel/TokenCacheHitStrip.swift` 24 行）、主图卡 163（`NetworkMonitor/Sources/NetworkMonitor/MenuPanel/TokenPaneView.swift` 114 行）、对照卡 50（同文件 141 行）。

取证台账实测两屏 `fill_ratio = 100.0%`、`blank = 0.0pt`、`inner_scrollable = NO`，pane 高度 overview=458.0 / distro=458.0（`.open-design/token-ia-r1/README.md` 42–55 行，生成脚本见 `NetworkMonitor/Sources/NetworkMonitor/Debug/TokenPaneSnapshot+Screens.swift` 29–48 行）。内容超出外框时走**屏内**滚动，页脚固定屏底不动；切屏后滚动归顶。

**为什么是 2 屏（演进说明）**：改造前是 4 屏（概览 / 用量 / 缓存 / 排行），每屏只用掉约 73% 内容预算（`fill_ratio ≈ 73%`、`blank ≈ 110pt`），每屏下方常年一片空白，看一次完整数据要切三次屏且上下文全丢（`.open-design/token-ia-r1/README.md` 57 行、`.open-design/token-ia-r1/decisions.md` 7–10 行）。三案对照（两屏 / 三屏 / 单屏内滚动）后取两屏案，理由是直接回应「屏数减半 + 每屏填满」两条诉求（同文件 12–25 行）。收敛后的分工：**总览 = 一眼看「现在用了多少、长什么样」**，**分布 = 一眼看「花在哪个工具 / 项目 / 模型上」**；每屏 4 块以上信息块，切屏成本减半。

**缓存命中降级为面板内二级页**：它的内容是「对一个比率的多角度展开」（环 + 四行拆分 / 命中率走势 / 本周期对照 / 样本统计 + 口径），摊满一屏也只填到 350pt（`NetworkMonitor/Sources/NetworkMonitor/MenuPanel/TokenCacheHitPage.swift` 9–21 行），故从独立第 3 屏降级为 `TokenDetailKind.cache`（`NetworkMonitor/Sources/NetworkMonitor/MenuPanel/TokenDetailPages.swift` 9–17 行）。主面板只留一条可点的命中率条：`TokenCacheHitStripView` 42pt（`NetworkMonitor/Sources/NetworkMonitor/MenuPanel/TokenCacheHitStrip.swift` 24 行），整条 onClick → `openDetail(.cache)`（`NetworkMonitor/Sources/NetworkMonitor/MenuPanel/TokenPaneView.swift` 132–134 行）。

**空缺口径**：`cachePage.series` 为 `[Double?]`，分母为 0 的桶（无会话的小时 / 天）= `nil`（长度不变，横轴对齐）；走势图遇 `nil` **断开**——不连线、不落底、面积不填到 0，孤立数据点画 2.8pt 圆点；卡头纵轴写真实 min–max（如「纵轴 97.4% – 98.9%」），整窗无数据写「无有效桶 · N 桶」，不再出现「0.0% – 98.7%」。

面板内二级页（覆盖式，不新开窗口，共 4 个，`NetworkMonitor/Sources/NetworkMonitor/MenuPanel/TokenDetailPages.swift` 13–17 行）：**缓存命中**（总览屏命中率条点进来）、**单桶详情**（点柱子，小时桶 / 日桶）、**按小时三段拆分**（主图卡点进来）、**天趋势明细**（主图卡头「14 天 ›」，上限 33 天）。二级页顶部是「‹ Token」返回条 + 当前页面包屑，内容纵向滚动；键盘焦点只给返回按钮（`NetworkMonitor/Sources/NetworkMonitor/MenuPanel/TokenDetailPages.swift` 86–98 行）。

改造前 `.cache` / `.projects` / `.models` 三个二级页曾并入对应屏，入口删除。本轮 `cache` 以「原缓存屏整块内容」的形态回到二级页，`projects` / `models` 仍留在分布屏的维度分段里（`NetworkMonitor/Sources/NetworkMonitorCore/Token/TokenPresentationModels.swift` 241–265 行，维度 = 工具 / 项目 / 模型）。

## 控件

- 屏切换：`TokenSegmentedControl`，标题 总览 / 分布；两段等宽（`expands: true`），与范围分段同族但更轻（第二行）——`NetworkMonitor/Sources/NetworkMonitor/MenuPanel/TokenPaneView.swift` 74 行。
- 键盘：`focusableRows` 按当前屏给（屏切换条 + 屏内卡片可聚焦；页脚不参与焦点）；二级页打开时只留返回入口（`NetworkMonitor/Sources/NetworkMonitor/MenuPanel/TokenPaneView.swift` 194–200 行）。
- 屏切换流程：切显隐 → 屏内滚动归顶 → render → `onContentChanged`（高度已恒定，通知保留用于 popover 尺寸同步）。
- 分布行：`TokenRankingScreenView` 整块自绘，Top 8 由 `DrawnRowList` 一次画完；卡片高度 = 内容预算 385 − 对照卡 50 − 间距 4 = 331pt（`NetworkMonitor/Sources/NetworkMonitor/MenuPanel/TokenPaneView.swift` 163 行）。**行高 34…64 自适应**（`NetworkMonitor/Sources/NetworkMonitor/MenuPanel/TokenScreenContent+Ranking.swift` 40–41 行）：按「卡内可用高度 ÷ 可见行数」算，封顶后剩余高度交给底部 spacer，不再 fillEqually 拉满；行数 ≥ 8 时汇总块与口径说明让位，保证行高不低于 34pt。右侧 tok / 占比的压缩阻力为 required（宽度紧张时截名称，不截数字）。
- 屏切换条 / 维度切换器：`TokenSegmentedControl` 的段内文字水平居中；`style: .inline` 用轨道底 + 选中 pill（卡底与控件同色时看不出可点，这是用户反馈的原问题），悬停给浅色反馈 + 手型光标，读屏标签「切换排行维度：工具 / 项目 / 模型」（`NetworkMonitor/Sources/NetworkMonitor/MenuPanel/TokenScreenContent+Ranking.swift` 81 行）。
- 主图刻度：左栏宽度按最长刻度标签算（`NetworkMonitor/Sources/NetworkMonitor/MenuPanel/TokenBarsView+Scale.swift` 52–58 行），值 = 归一化基准 × 比例（0 / 中值 / 峰值），用 `TokenFormatting.abbreviated` 化简（跟随设置页「数值单位」），横轴刻度行按同一宽度右移对齐；网格为 4 条水平虚线（25 % / 50 % / 75 % / 100 %，同文件 18–24 行），刻度栏内点击不算选列。

## 代码落点

| 层 | 文件（相对仓库根） | 改动 |
|---|---|---|
| UI 纯逻辑（可测） | `NetworkMonitor/Sources/NetworkMonitorUI/Token/TokenScreen.swift` | `enum TokenScreen`（overview / distro）+ title + `TokenScreenBlock` 分区契约（6 个区块，每个唯一归属一屏）+ `TokenScreenFooter` |
| 视图 | `NetworkMonitor/Sources/NetworkMonitor/MenuPanel/TokenPaneView.swift` | `screen` 状态、两段 `screenControl`、`screenHeight` 409 / `screenContentHeight` 385、缓存命中条、主图卡 163pt |
| 视图 | `NetworkMonitor/Sources/NetworkMonitor/MenuPanel/TokenScreenFrameView.swift` | 屏外框：固定高度 + 内容滚动区 + 页脚 |
| 视图 | `NetworkMonitor/Sources/NetworkMonitor/MenuPanel/TokenPaneView+Layout.swift` | 2 个屏外框装配（内容按 `TokenScreen.blocks`、页脚按 `TokenScreen.footer`，64–106 行） |
| 视图 | `NetworkMonitor/Sources/NetworkMonitor/MenuPanel/TokenPaneView+Render.swift` | 两屏渲染；两屏各一个状态带实例、共用同一份 `model.stateBand`（94–99 行） |
| 视图 | `NetworkMonitor/Sources/NetworkMonitor/MenuPanel/TokenScreenContent.swift` | 分布卡与二级页共用的卡片组件（`TokenContentKit`） |
| 视图 | `NetworkMonitor/Sources/NetworkMonitor/MenuPanel/TokenCacheHitStrip.swift` | 总览屏「缓存命中」紧凑条 42pt（数据取 `cachePage`） |
| 视图 | `NetworkMonitor/Sources/NetworkMonitor/MenuPanel/TokenScreenContent+Ranking.swift` | 分布屏：维度分段 + 占比条 + Top 8 + 汇总 + 单行口径 |
| 视图 | `NetworkMonitor/Sources/NetworkMonitor/MenuPanel/TokenScreenContent+Ranking+Layout.swift` | 分布屏行高 34…64 自适应 |
| 视图 | `NetworkMonitor/Sources/NetworkMonitor/MenuPanel/TokenCacheHitPage.swift` | 缓存命中二级页（原缓存屏整块内容） |
| 视图 | `NetworkMonitor/Sources/NetworkMonitor/MenuPanel/TokenDetailPages.swift` | `TokenDetailKind` = cache / hourly / bucket / trend |
| 快照 | `NetworkMonitor/Sources/NetworkMonitor/Debug/TokenPaneSnapshot+Screens.swift` | 两屏 × 浅深取证，台账给出 fill_ratio / 空白 / pane 高度一致判据 |
| 测试 | `NetworkMonitor/Sources/TestRunner/TokenScreenTests.swift` | 2 屏契约：标题与顺序 / 区块唯一归属 / 每屏页脚 |

## 硬约束

- 数据口径一个都不改：所有数值仍来自 `TokenPaneModel`（Core 派生），视图只搬运。
- 文件 ≤500 行 / ≤15 KiB，超了按「主类 + 扩展文件」拆。
- 新增纯逻辑优先配 TestRunner 断言（`TokenScreen` 的标题 / 顺序 / 区块归属唯一性 / 每屏页脚）。
- 空缺口径由 Core 表达（`series: [Double?]`），视图把 `nil` 原样交给绘制处理（不折算成 0 再画）。
- 编译 `swift build --disable-sandbox --build-system native`、测试 `swift run … TestRunner` 全绿、`bash NetworkMonitor/Scripts/check-file-size.sh` 通过。

## 验收

1. 两屏各自截图（浅/深）可读：总览的 Hero + 四族卡 + 缓存条 + 主图一路填到页脚上方；分布卡撑到页脚上方，行前色点与占比条同色。
2. 台账给出「内容占可视区比例 / 剩余空白」：两屏 `fill_ratio = 100%`、`blank = 0pt`（取证 `.open-design/token-ia-r1/README.md` 42–55 行）；回归以 100% 为基准，台账出现 `blank > 0` 即视为密度退化。
3. **两屏 pane 高度一致**（台账 `pane 高度一致 = YES`，实测两屏恒 458pt），无 Auto Layout 冲突；切屏后滚动归顶。
4. 缓存命中二级页 24 桶有空缺时：折线在缺口断开、纵轴写真实 min–max，不出现「0.0%」起点。
5. 同一范围下，两屏数字与改造前对应区块一致（抽查 hero 总量、缓存命中率、工具 Top1）。
6. 屏切换后键盘焦点不丢失、Esc 在二级页返回。
7. 快照命令：`NM_SNAPSHOT_DIR=/tmp/nm-shots <包内可执行文件>`，产出 2 屏 × 2 外观 + `menu-token-screens.txt` 台账。
