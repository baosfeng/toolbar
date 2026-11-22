# Token 多来源接入 —— 数据源格式与交互设计规格

> 状态：**已全部实现**——七源全接（DSH / Claude Code / Codex / Gemini CLI / Copilot CLI / OpenCode / Zed）+ 来源切换 + 设置页来源清单 + 后台自动监控；Cursor 按 §2.8 只保留额度监控 · 取证日期 2026-11-22 · 前置调研见 [Agent token 用量监控扩展调研](../调研/agent-token用量监控-扩展调研.md)
>
> 实现补记（与规格的差异，都有据）：① 来源读取分两类——文件型（DSH / Claude / Codex / Gemini）与会话单位型（Copilot / OpenCode / Zed 走 SQLite，判据是 **db 文件**而非目录，`defaultRoots` 语义是 db 路径）；② Gemini 用**文档级**入口（一份文件可能多事件），不套逐行协议；③ 请求数按事件行计数，Zed 的合成差额记录会让该会话 +1（可接受，改需表加列 + 迁移）；④ 坏库落「黄：有目标无数据」而不是灰。
>
> 目标：Token 页从「只有 DSH」扩到多家编码 agent；用户可在 Token 页切换来源，在设置页配置后由后台自动增量监控。

## 0 目标与非目标

**做**：Claude Code、Codex CLI、Gemini CLI、Copilot CLI、OpenCode、Zed 六家的本地用量接入；Token 页来源切换；设置页来源清单与后台自动监控。

**不做**：Cursor 本地 token（本地无真实计数，见 §2.8）；任何依赖 Cookie / 私有接口的抓取；把估算值混进精确统计。

## 1 现状里能复用的东西

| 现有件 | 复用方式 |
|--------|----------|
| `HarnessTokenUsage`（四桶 + 请求数） | 作为所有来源的统一口径，不改 |
| `harness_token_event` / `harness_session_scan` | 加 `source` 列，一套表存全部来源 |
| `(size, mtime)` 增量判据 | 每家照用，避免全量重扫 |
| `HarnessZstdDecoder` / `HarnessZstdLineStreamer` | DSH 与 Zed 都要 zstd；Zed 是整块解压，DSH 是流式 |
| 页头 `PaneHeaderRowView` + `hostLabel` | `hostLabel` 已是「DSH · N 会话」，天然留了来源位 |
| `AppEvents.harnessUsageChanged` | 后台扫完发事件，面板已订阅 |

**现状缺口**：`refreshIfNeeded` 在生产代码里只有面板动作会触发（`MenuPanelController+Actions.swift:94`），没有后台定时 —— 这正是「自动监控」要补的部分。

## 2 数据源格式规格

### 2.0 通用约定

- **行包封**：除 DSH / Zed（SQLite）外都是 JSONL，一行一个 JSON 对象；坏行跳过并计数，绝不整文件失败。
- **时间**：Claude 用 ISO8601（`2026-01-05T10:00:05.000Z`）；Codex 有行级 `timestamp` 字段；Gemini 记录内 `timestamp`；OpenCode 是 unix **毫秒**；Zed 无逐请求时间（用 thread 的 `updated_at`）；Copilot 每请求有真实时间戳。统一换算到 **epoch 毫秒**。
- **编码**：全部 UTF-8；Claude / Codex 的 `cwd` 可能是 Windows 路径（fixture 里就有 `C:\\Users\\…`），不要假设 POSIX。
- **可空**：用量对象可能整体缺失或为 `null` —— 跳过该行，不要补 0 记账。

### 2.1 Claude Code

**位置**

```text
~/.claude/projects/<sanitized-cwd>/<sessionId>.jsonl           # 旧：扁平
~/.claude/projects/<sanitized-cwd>/<sessionId>/<file>.jsonl    # 新：嵌套
~/.config/claude/projects/…                                    # 另一默认根
```

`CLAUDE_CONFIG_DIR` 支持逗号分隔多根，多根结果合并。

**样例**（取自公开 fixture，仅结构真实）

```json
{"parentUuid":"u-1","isSidechain":false,"type":"assistant",
 "message":{"model":"claude-sonnet-4-6","id":"msg_a1","role":"assistant",
   "content":[{"type":"text","text":"…"}],
   "usage":{"input_tokens":1000,"output_tokens":500,
            "cache_read_input_tokens":2000,"cache_creation_input_tokens":3000}},
 "requestId":"req_1","uuid":"a-1","timestamp":"2026-01-05T10:00:05.000Z",
 "sessionId":"fix-aaaa-1111","cwd":"…","version":"2.1.140","gitBranch":"main"}
```

**字段表**

| 字段 | 类型 | 可空 | 用途 |
|------|------|-----|------|
| `type` | string | 否 | 只处理 `assistant`；`user` / `system` / `attachment` / `file-history-snapshot` 等一律忽略 |
| `message.id` | string | 否 | **去重主键** |
| `message.model` | string | 是 | 模型维度 |
| `message.usage.input_tokens` | int | 是 | uncachedInput |
| `message.usage.output_tokens` | int | 是 | output |
| `message.usage.cache_read_input_tokens` | int | 是 | cacheRead |
| `message.usage.cache_creation_input_tokens` | int | 是 | cacheWrite |
| `requestId` | string | 是 | 去重副键 |
| `timestamp` | ISO8601 | 否 | 分天 |
| `sessionId` / `cwd` | string | 是 | 会话 / 项目维度 |
| `isSidechain` | bool | 是 | true = 子 agent 重放，见下 |

**解析规则**

1. 只认 `type == "assistant"` 且 `message.usage` 存在。
2. **同一 `message.id` 的多行只记一次**：一条 API 响应按 content block 拆成多行，`usage` 逐字节相同。fixture 里 `msg_a1` 出现两行、两份 usage 完全一致。两处实测：社区数据 7166 行 → 2708 个唯一 id（约 2.6 倍）；公开 fixture 10 行 → 9 条唯一，输入合计 2080 → 1080（**1.96 倍虚高**）。不去重就是假数。
3. **sidechain 副本丢弃**：`isSidechain: true` 且与父条目 `message.id` 相同（`requestId` 不同）时，保留父条目。
4. 无 `message.id` 的退化行按 (`sessionId`, `timestamp`, 四桶) 去重。

**退化**：坏行（fixture 第一行就是 `{this line is intentionally malformed json`）计入 `malformedLines`，不中断。

### 2.2 Codex CLI

**位置**

```text
$CODEX_HOME（默认 ~/.codex）/
  sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl
  archived_sessions/YYYY/MM/DD/rollout-*.jsonl
```

同一会话可能同时存在于 `sessions/` 与 `archived_sessions/`，按「相对路径 + 文件名」去重，活跃副本优先。

**样例（≥0.44 包封）**

```json
{"timestamp":"2026-01-05T10:00:00.000Z","type":"session_meta",
 "payload":{"id":"cdx-session-1","cwd":"…","originator":"codex_cli_rs","cli_version":"0.50.0","git":{"branch":"main"}}}
{"timestamp":"2026-01-05T10:00:01.000Z","type":"turn_context",
 "payload":{"cwd":"…","model":"gpt-5.1-codex","approval_policy":"on-request"}}
{"timestamp":"2026-01-05T10:00:15.000Z","type":"event_msg","payload":{"type":"token_count","info":{
  "last_token_usage":{"input_tokens":1000,"cached_input_tokens":250,
    "output_tokens":125,"reasoning_output_tokens":75,"total_tokens":1200},
  "total_token_usage":{"…同上形状，累计…":0},
  "model_context_window":272000}}}
```

**样例（老格式，无用量）**

```json
{"id":"old-codex-1","timestamp":"2025-08-10T09:00:00.000Z","instructions":"…","cwd":"…"}
{"type":"message","role":"user","content":[{"type":"input_text","text":"list the files here"}]}
```

老格式**没有行包封、没有 timestamp、没有 token_count** —— 解析器要能识别并归入「该文件无用量」，而不是报错。

**字段表**

| 字段 | 用途 |
|------|------|
| `type` | `session_meta`（cwd/模型兜底）、`turn_context`（`payload.model` 的规范来源）、`event_msg`（只关心 `payload.type == "token_count"`） |
| `payload.info.last_token_usage` | **首选**：当轮用量 |
| `payload.info.total_token_usage` | 仅当没有 `last_token_usage` 时，做**字段级差分** |
| `input_tokens` / `cached_input_tokens` | `cached` 是 `input` 的**子集** |
| `output_tokens` / `reasoning_output_tokens` | reasoning **已含在** output 里 |
| `total_tokens` | 仅供自检 |

**解析规则**

1. `info` 为 `null` → 跳过该行。
2. `uncachedInput = input_tokens - cached_input_tokens`，`cacheRead = cached_input_tokens`，`cacheWrite = 0`。
3. 只有累计值时：本行 = 本次累计 − 上次累计（按字段各自差分）。
4. **累计回退**（compaction / fork / 陈旧快照）：重设基线，本次记 0，不记负数。
5. fork 会话会在文件开头**重放父会话的 token_count 行**（时间戳早于本文件 `session_meta`）：跳过。
6. 模型取当前生效的 `turn_context.payload.model`；拿不到时用 `token_count.payload.info.model`（新版有）→ 仍无则 `unknown`。

**退化**：`2025-09-06` 之前的文件完全没有 token 遥测，属正常「空用量」，不是错误。

### 2.3 Gemini CLI

**位置**

```text
$GEMINI_CLI_HOME/.gemini（默认 ~/.gemini）/ tmp/<项目 slug>/chats/session-<UTC>-<8位>.jsonl
```

旧版是 `session-*.json`（整份 JSON），且旧桶名是 project root 的 sha256（迁移时会复制，可能双份）。

**字段表**（`tokens` 为归一化名，源码映射见括号）

| 字段 | 映射自 | 用途 |
|------|--------|------|
| `tokens.input` | `promptTokenCount` | 含缓存的输入 |
| `tokens.output` | `candidatesTokenCount` | output |
| `tokens.cached` | `cachedContentTokenCount` | cacheRead |
| `tokens.thoughts` | `thoughtsTokenCount` | 单列，**要加进 output** |
| `tokens.tool` | `toolUsePromptTokenCount` | 计入输入 |
| `tokens.total` | `totalTokenCount` | 自检 |

**解析规则**：`uncachedInput = input - cached`、`output = output + thoughts`；`tokens` 可能为 `null` → 跳过；`$set.messages` 全量重写 → 按消息 id 去重。

**关键约束**：Gemini **默认只保留 30 天并自动删除**。接入后必须尽快沉淀进索引，晚接入就会永久缺历史。

### 2.4 Copilot CLI

**位置**：`~/.copilot/session-store.db`（SQLite，WAL）

**表 `assistant_usage_events`**：一次 API 请求一行 —— `input_tokens`（**cache-inclusive**）、`output_tokens`、cache read / write、reasoning、模型、真实请求时间戳。这是 CLI 与桌面 App 会话的权威输入/缓存来源。

VS Code 侧另有一套 delta journal（`kind:0` 设根对象、`kind:1` 按路径写值、`kind:2` 往数组追加），同一会话两种格式共用 `copilot-chatsession:` 键去重。首版只接 CLI 的 SQLite，VS Code 侧留待后续。

**解析规则**：`uncachedInput = input_tokens - cache_read`；reasoning 视表内有独立列则单列，否则视为已含。

### 2.5 OpenCode

**位置**：`~/.local/share/opencode/opencode.db`（SQLite WAL，**只读打开**：`mode=ro` + `PRAGMA query_only`，CLI 可能正持有它）

**相关表/字段**

- `message(id, session_id, time_created, data)`：`data.tokens = {total, input, output, reasoning, cache:{read, write}}`、`data.modelID`、`data.providerID`、`data.cost`
- `session(id, project_id, parent_id, directory, cost, tokens_input, tokens_output, …)`：`directory` 即 cwd；`parent_id` 非空 = 子 agent 会话
- 时间全部是 unix **毫秒**

**解析规则**：`output = output + reasoning`；`cost` 常为 0（本地/订阅 provider），不要拿它当主数据；旧版是 `storage/` JSON 树，检测到 db 存在就只读 db，避免双算。

### 2.6 Zed

**位置**：`~/Library/Application Support/Zed/threads/threads.db`

**结构**：`threads(id, summary, updated_at, data_type, data)`；`data` 是 **zstd 压缩的 JSON**（`data_type = "zstd"`，旧行可能是 `"json"`，两种都要读）。

解压后含：

- `model: {provider, model}`
- `request_token_usage`：用户消息 id → `{input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens}`（0 值字段省略）
- `cumulative_token_usage`：整条 thread 合计

**两个必须处理的点**：

1. `request_token_usage` **覆盖不全**（实测累计约为 map 之和的 3 倍）→ 每条 thread 补一条 `cumulative-remainder` 差额记录，保证总数与 `cumulative_token_usage` 对齐。
2. **没有逐请求时间戳** → 该 thread 的全部调用都算在 `updated_at` 上，分天粒度只能到天、且可能整体偏移。

### 2.7 各源四桶映射汇总

| 来源 | uncachedInput | output | cacheRead | cacheWrite |
|------|---------------|--------|-----------|------------|
| DSH | `inputTokens` | `outputTokens` | `cacheReadTokens` | `cacheWriteTokens` |
| Claude Code | `input_tokens` | `output_tokens` | `cache_read_input_tokens` | `cache_creation_input_tokens` |
| Codex | `input - cached` | `output_tokens`（含 reasoning） | `cached_input_tokens` | 0 |
| Gemini | `input - cached` | `output + thoughts` | `cached` | 0 |
| Copilot | `input_tokens - cache_read` | `output_tokens` | cache read | cache write |
| OpenCode | `input` | `output + reasoning` | `cache.read` | `cache.write` |
| Zed | `input_tokens` | `output_tokens` | `cache_read_input_tokens` | `cache_creation_input_tokens` |

「input 是否含 cache」是分水岭：DSH / Claude / Zed 互斥，Codex / Gemini / Copilot 包含。

### 2.8 Cursor（不可接入，仅记录原因）

本地三处都不含逐轮 token：`agent-transcripts/*.jsonl` 只有消息与工具调用；`bubbleId.tokenCount` 当前版本恒 0；`composerData.promptTokenBreakdown.totalUsedTokens` 只是某次上下文占用，不能按天求和；缓存命中恒 0。真实值只在服务端（`export-usage-events-csv`）且需 Cookie/钥匙串解密。**结论：Token 页不出现 Cursor**；它的额度继续在额度页。

## 3 Token tab 的来源切换

### 3.1 位置：页头左侧的页名

现在页头是 `PaneHeaderRowView(title: TokenPaneView.pageTitle)`（`pageTitle = "DSH"`，见 `NetworkMonitor/MenuPanel/TokenPaneView.swift`），右半是「会话数 → 范围分段 → 刷新」。把**页名换成来源切换器**：

```text
[ 全部 ▾ ] · 1,284 会话        [今日|7天|30天]  [⟳]
```

- 点击页名弹出 `NSMenu`：**全部** / DSH / Claude Code / Codex / Gemini CLI / Copilot CLI / OpenCode / Zed。
- 只列**已启用且有发现**的来源；未安装的源不出现在菜单里（它属于设置页的事）。
- 单项来源选中后，`hostLabel` 变成 `"Claude Code · 42 会话"`。
- 选择持久化到 `token.selectedSource`（默认 `all`）；来源被删/禁用后回落 `all`。

**为什么不用分段控件**：来源数是 1..8 个，可变且会增长；页头已有范围分段，再并排一个分段会挤压宽度（296pt 面板）。下拉是一行恒定宽度。

**宽度预算（实测后定稿）**：内容宽 296pt，页头现有占用约 254pt（标题 22 + meta 60 + 范围分段 130 + 刷新 24 + 间距），只剩约 40pt，而「Claude Code ▾」需要约 78pt。定稿：

| 元素 | 处理 |
|------|------|
| 标题位 | 换成来源切换控件（约 78pt）——`PaneHeaderRowView` 需新增 `setTitleControl(_:)` |
| meta（会话数） | 去掉来源名前缀，只留「N 会话」（约 60pt→48pt，可截断） |
| 范围分段 | **不动**（130pt，高频操作） |
| 刷新 | **不动**（24pt） |

**硬约束**：页头恒 22pt，控件塞进这一行时高度代价为零；**绝不新增第二行**——四屏外框 409pt 已写死，用量屏自然高 398pt 只剩 11pt 余量，加行会把四屏全部挤破。`PaneHeaderRowView` 是五页共用骨架，改完必须复验另外四页截图无变化。

### 3.2 「全部」视图的口径

- Hero / 四族卡 / 图与趋势 / 缓存：**跨源求和**，四桶已统一，可直接相加。
- 排行屏：在「按项目 / 按模型」之外增加第三段「**按工具**」；「全部」时默认落在「按工具」。
- 缓存命中率跨源合并后仍然有意义（分子分母同口径），但要在缓存屏脚注写明「跨 N 个来源合并」。

### 3.3 空态与不可用态

沿用现有三分法，但按源报：

| 情况 | 文案方向 |
|------|----------|
| 源未安装（目录不存在） | 「未检测到 Claude Code」（设置页里也不出现该行，或出现但置灰） |
| 源已装但无会话 | 「还没有可统计的会话」 |
| 目录存在不可读 | 「目录不可读，检查权限或卷」 |
| 版本无遥测（Codex < 2025-09） | 「该目录的会话没有 token 记录」 |

## 4 设置页配置

### 4.1 「数据来源」卡 → 来源清单

由现在的一行目录改成一张清单，每个来源一行（复刻额度 Provider 的实例行形态）：

```text
数据来源
  ● Claude Code     ~/.claude/projects          42 会话 / 1.2k 事件   [开关]
  ● Codex           ~/.codex/sessions           18 会话 / 640 事件    [开关]
  ○ Gemini CLI      未检测到                                          [开关]
```

**不用「⋯」弹出菜单**：设置页全目录零 NSMenu 先例（只有 `NSPopUpButton`），新写一套范式还要处理深色与焦点。改为：

- 行尾只放**启用开关**；
- 「选择目录…」做成路径行内链接（仅该项已启用时出现，沿用 `SettingsLinkButton`）；
- 「重新扫描 / 清空该源索引」统一放进下方**索引卡的维护区**，按来源下拉选择后执行。

零新控件范式，交互点也少一次。

- 状态点语义：绿 = 可读且有数据；黄 = 可读但无数据 / 版本无遥测；灰 = 未安装；红 = 不可读。
- 关闭开关 = 该源不参与索引与「全部」统计（已有数据保留，切回来即恢复）。
- 每源的目录偏好键：`token.source.<id>.rootPath`（缺省走各自默认路径 + 环境变量）。

### 4.2 后台自动监控

新增一行总开关（放在「数据来源」卡首行）：

```text
后台自动监控  [开]   每 [5 分钟 ▾] 增量扫描已启用的来源
```

- 偏好键：`token.autoIndex.enabled`、`token.autoIndex.interval`（默认 **300**，可选 60 / 300 / 900 / 1800）。
- **缺键即关**（遵循项目「后台能力默认关、升级零行为变化」的惯例），但落地「配置好之后自动监控」的方式是：**用户在设置页首次启用任一来源时，自动把 `enabled` 置为 true**，并在该行下方显示一行说明。用户随时可关。
- 间隔下限 60s：现有增量按 `(size, mtime)` 跳过未变更文件，空跑成本只有一次目录枚举 + 一次 SQLite 查询。

### 4.3 「索引」卡

从三行（会话 / 事件 / 最近扫描）扩为：总量三行 + **按来源分组的会话/事件数** + 最近扫描时间（每源）。数据来自 `harness_session_scan` 按 `source` 聚合。

### 4.4 偏好键命名空间

代码现状只有 `harness.sessionsRootPath` 一个 token 相关键（`harness.*` 是 DSH 时期的命名）。多来源后**统一用 `token.*`**，集中放在一个 `TokenSourcePreferences` 类型里（照 `BillingProviderPreferences` 的 keyPrefix + `storageKey(for:)` 形态），不在各处散字符串：

| 键 | 含义 |
|----|------|
| `token.selectedSource` | Token 页当前来源（缺省 `all`） |
| `token.source.<id>.enabled` | 该来源是否参与索引 |
| `token.source.<id>.rootPath` | 该来源的自定义根目录（缺省走默认路径 + 环境变量） |
| `token.autoIndex.enabled` | 后台自动监控总开关 |
| `token.autoIndex.interval` | 扫描间隔秒数 |

**旧键不改名**（进 UserDefaults 就不可改名）：`harness.sessionsRootPath` 保留为 **dsh 源**的根目录键，`token.source.dsh.rootPath` 缺省时回落读它 —— 老用户零迁移，新键语义一致。

## 5 自动监控的实现

### 5.1 触发策略

| 触发 | 时机 | 说明 |
|------|------|------|
| 定时器 | 按 `token.autoIndex.interval` | 主路径；只跑增量 |
| 面板打开 Token 页 | 切到该 tab | 已有的 `refreshIfNeeded` 保留 |
| 设置页动作 | 改目录 / 改开关 / 点重扫 | 立即生效 |
| 系统唤醒 | `NSWorkspace.didWakeNotification` | 休眠期间定时器不走，唤醒后补一次 |
| 锁屏 / 睡眠 | 暂停 | 复用现有暂停态口径，唤醒后恢复 |

**不用 FSEvents**：多来源目录 + zstd 追加写 + 高频工具事件会产生事件风暴，还要做防抖与合并；定时增量已经足够（未变更文件零成本），实现与调试都更简单。

### 5.2 装配与内存边界

- 索引服务 `HarnessUsageService` **已经**在 `AppAssemblyStages+Features.swift:138` 常驻装配，调度器挂在它旁边即可，不需要改动面板的懒装配。
- 面板视图仍懒装配：定时器只跑索引与聚合，**不创建视图**；扫完发 `AppEvents.harnessUsageChanged`，面板开着就更新，没开就只更新缓存快照。
- 面板未打开时不做全表聚合（现有 `publishSnapshot(force:)` 已区分），避免无意义 CPU。

### 5.3 状态与节流

- 调度器是单线程队列，同一时刻只允许一轮；排队中的请求按最广范围合并（现有 `HarnessRebuildQueue` 已实现，直接复用）。
- 一轮结束后算下一次触发时间；若本轮耗时超过间隔，按「本轮结束 + 间隔」顺延，不追帧。
- 状态对外只暴露：空闲 / 扫描中（进度）/ 暂停 / 失败（原因），沿用 `HarnessIndexingState`。

## 6 索引与数据模型改动

```sql
ALTER TABLE harness_token_event  ADD COLUMN source TEXT NOT NULL DEFAULT 'dsh';
ALTER TABLE harness_session_scan ADD COLUMN source TEXT NOT NULL DEFAULT 'dsh';
CREATE INDEX IF NOT EXISTS idx_harness_event_source ON harness_token_event(source);
```

- 默认值 `'dsh'` 让既有数据零迁移；`CREATE INDEX IF NOT EXISTS` 保证幂等（现有建表函数可重复执行）。
- 聚合快照按 `source` 分组一次查出，`HarnessUsageSnapshot` 增加 `bySource: [TokenSourceID: HarnessSourceUsage]`（计数器 + 会话数）。
- **单源视图必须与全量同形**：另加 `scoped(to source: TokenSourceID) -> HarnessUsageSnapshot`，返回含日/时桶、项目/模型、窗口聚合的完整快照。`bySource` 只够画「有哪些来源」，画不了四屏——这条是实现期补的契约缺口。
- `HarnessParsedEvent` 扩展：`session(cwd:model:)`、`message(…)` 不变，新增每个来源自己的 parser 类型，统一实现 `TokenLineParsing`。

## 7 验收

每个来源一份 fixture（可从公开 fixture 抄结构、数据自行造），断言：

| 来源 | 必须写的用例 |
|------|--------------|
| Claude Code | 同 `message.id` 三行 → 只算一次；`isSidechain` 副本丢弃；坏行计入 malformed；无 `requestId` 时三元组去重 |
| Codex | `last_token_usage` 优先；只有累计时差分正确；累计回退不记负数；fork 重放行跳过；老格式文件归为无用量 |
| Gemini | `input - cached`；`output + thoughts`；`tokens: null` 跳过 |
| Copilot | `input_tokens - cache_read`；只读打开 `session-store.db` |
| OpenCode | `output + reasoning`；`parent_id` 子会话照常计入 |
| Zed | zstd 解压；`cumulative-remainder` 补齐后与 `cumulative_token_usage` 相等 |
| 切换 | 选单源 → 四屏数字等于该源聚合；选「全部」→ 等于各源之和 |
| 自动监控 | 关开关 → 定时器不跑；开开关 → 到点增量、无变更文件不重算 |

## 8 分阶段

1. **P1**：索引加 `source` 列 + Claude Code / Codex 两个解析器 + 页头来源切换 + 设置页来源清单 + 自动监控调度器。这两家本地数据最可靠、社区实现可交叉验证。
2. **P2**：Gemini CLI、OpenCode（SQLite 只读）、Copilot CLI（`assistant_usage_events`，质量最高）、Zed（zstd + 差额补齐）。
3. **P3**：VS Code Copilot 的 delta journal、Cursor 官方导出通道（需明确标记「导入」且不与本地扫描混算）。

## 9 风险

| 风险 | 对策 |
|------|------|
| 上游格式漂移 | 每家都按「观察所得非契约」处理：字段缺失即跳过，坏行计数进诊断 |
| 隐私 | 只读用量字段，正文不落库、不进日志；设置页不展示样本行 |
| 上游清理（Gemini 30 天 / Claude prune） | 索引即账本，必须持续增量沉淀，不能改成每次重算 |
| 性能 | `(size, mtime)` 增量 + 单线程排队；Zed 整块 zstd 解压注意内存峰值 |
| 时间口径 | 全源统一到 epoch 毫秒再分天；Zed 只能到天且可能偏移，需在界面标注 |
