# DSH Token 用量监控设计规格

> 何时阅读：维护「Token」tab、改动 DSH 会话索引或 token 口径时。

## 目标

菜单面板第 5 个分段「Token」：把本机 DeepSeek Harness（DSH）的 token 消耗做成可长期观察的监控页——今日/本周/累计总量、按小时与按天趋势、项目与模型分布、缓存复用率。数据全部来自本机会话文件，不联网。

## 数据源

`~/.dsh/sessions/<编码后的 cwd>/<sessionID>/session*.jsonl.zstd`（zstd 压缩的 JSONL 事件流，实测 1048 个文件 / 514MB / 2026-09-07 起）。取两类事件：

| 事件 | 字段 | 用途 |
|---|---|---|
| `type == "session"` | `cwd` | 项目归属（**只认这一处**，不从目录名反解） |
| `type == "assistant/message"` | `time`（UTC 毫秒）、`data.usage.{inputTokens, outputTokens, cacheReadTokens}` | token 计数与时间分桶 |

带 usage 的消息覆盖率实测 99.95%（72669/72704）。

## 口径

- `inputTokens` = **未缓存输入**（不含缓存命中部分），`cacheReadTokens` = 缓存命中读；两者相加再加 output 才等于 `totalTokens`。
- 缓存复用率 = `cacheRead / (cacheRead + uncachedInput)`，分母为 0 时返回 `nil` 而不是 0。
- 时区固定 `Asia/Shanghai`，周从周一开始；今日/昨日边界同此。
- 无会话的日期与小时**保留为空缺**，不补 0、不插值，UI 画斜纹。

## 关键决策

### 1. 同一会话多版本文件必须去重

部分会话目录同时存在 `session.jsonl.zstd`、`session.v3.jsonl.zstd`、`session.v4.jsonl.zstd`。逐文件累加会把同一段对话算两遍（实测重复 809 条事件 ≈ 160 万未缓存输入 + 1.19 亿缓存读）。

去重键用**内容键**（time + provider + model + 四项计数），不是 `id`、也不是 `seq`：

- 旧格式事件没有 `id`，按 id 判重会漏；
- `seq` 在同会话跨版本会**重启**（实例：session.jsonl 从 321 起、同会话 v3 从 20 起），用 seq 判重只能去掉 1 条、实际该去 189 条，全量会多算 259 条事件（uncached +0.26%）。

### 2. 增量索引

按 `(path, size, mtime)` 判断会话文件是否变化，未变跳过。正在写入的会话文件 size 会变，下次刷新重扫该文件，这是预期行为，不触发全表重建。

### 3. 首轮全量不阻塞 UI

首轮 140s 量级，跑在后台串行队列：面板打开先渲染上一轮快照（可为空态），完成后发 `AppEvents.harnessUsageChanged` 刷新；索引中显示「已索引 / 总数」。

### 4. 按小时聚合

一条 SQL 复用 `harness_token_event`（`((ts_ms/1000 + 28800) / 3600) % 24` 分桶），不新建表。今日未到的小时与无会话的小时均返回 `nil`，UI 画斜纹而非 0 柱。

## 架构落点

| 层 | 文件 |
|---|---|
| Core 模型 | `NetworkMonitorCore/Harness/HarnessTokenModels.swift` |
| 协议 | `HarnessTokenProtocols.swift`（本域专用，未上提 Domain/Protocols） |
| 扫描 | `HarnessSessionFile` / `HarnessSessionScanner` / `HarnessZstdLineStreamer` / `HarnessEventParser` |
| 索引与聚合 | `HarnessUsageIndexStore` / `HarnessUsageIndexAggregation` |
| 门面 | `HarnessUsageService`（refreshIfNeeded / rebuildIndex / snapshot） |
| 时间窗口 | `HarnessTokenTimeWindow`（今日/本周边界、小时索引） |
| 格式化 | `NetworkMonitorCore/Infrastructure/TokenUsageFormatting.swift` 与 `NumberUnitPreferences.swift`（量级化简纯函数，供 TestRunner 断言；档位跟随设置页「显示 › 数值单位」） |
| UI | `MenuPanel/TokenPane*.swift`、`TokenHourlyChartView`、`TokenTrendChartView`、`TokenMiniCharts`、`TokenCollapsibleSection` |

表：`harness_token_event(session_id, cwd, provider, model, ts_ms, uncached_in, output, cache_read, cache_write)` + `harness_session_scan(path, session_id, size, mtime_ms, scanned_at)`。

事件：`AppEvents.harnessUsageChanged / postHarnessUsageChanged`。

## 性能（实测）

| 场景 | 耗时 |
|---|---|
| 首轮全量（1048 文件 / 514MB） | 139.95s |
| 增量（无变更） | 3.78s |
| 增量（3 个会话在写） | 0.83s |

## 界面

原型定稿：`docs/设计/harness-token-监控-原型/`（c 版）与 `.open-design/harness-token-prototype/`。实现与原型的逐锚点对照见 `variants.md`，偏差报备 5 项（hero 高度、趋势图高度、项目清单高度、页脚高度、配色改用系统语义色）。

首屏常驻：页头（范围分段）→ Hero → 四族卡 → 按小时 24 桶图 → 缓存命中率卡 → 按项目 / 按模型两张半宽卡 → 状态带。

**范围一致性（三条线同源）**：范围分段（今日 / 近 7 天 / 近 30 天）是唯一口径源，Hero、四族卡、按项目、按模型、比较卡全部取同一个 `HarnessUsageWindow`；占比分母是该窗口内**全部**项目 / 模型的合计，不是列表 TopN 行的求和。二级页（按项目 / 按模型）的面包屑、Hero 副标题、说明卡文案由 `TokenDerive.distroCopy(range:)` 派生，视图只透传 —— 避免再出现「上面跟随范围、下面写累计口径」。

**悬停文案**：296pt 宽放不下 provider 前缀，同名模型（如 ollama 与 open-design 各自的 deepseek-v4.1-flash）在主面板正文里完全一样，provider 只在悬停文案里给出。文案由 Core 的 `TokenDistroRow.tip` / `TokenDerive.stackBarTip` 生成，覆盖分布行、占比条、图例项，视图只负责塞进 `toolTip`。

## 已知限制

- 依赖外部 `zstd` 二进制（优先 `/opt/homebrew/bin/zstd`，再查 PATH）；缺失时降级为明确的「数据源不可用」状态，不崩溃、不静默空数据。
- `cacheWrite` 在当前数据源恒为 0（DSH 未上报非零值）。
- 「缓存命中」二级页三块各自固定口径（主数值今日、走势与均值 30 天、逐桶今日 24 桶），不随主面板范围切换 —— 与「按项目 / 按模型」跟随范围不同，是刻意的。
- 图表为 NSView + CoreGraphics 手绘（项目未引入 Charts 依赖）：逐柱的数值不进 toolTip（24 列柱子面积太小），柱上信息走点击进入的二级页；分布行 / 占比条 / 图例有 tooltip。
- 展开态高度用实测 `fittingSize`，后续往折叠区内加内容需回归高度。
