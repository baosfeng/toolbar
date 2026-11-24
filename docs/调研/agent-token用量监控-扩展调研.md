# Agent token 用量监控扩展调研（Claude Code / Codex / Cursor 等）

> 状态：调研（未实施）· 取证日期 2026-11-22 · 取证人：lead
>
> 目标：回答「Token 页目前只能统计 DeepSeek Harness，能不能把 Codex / Claude / Cursor 等也接进来」，并给出可执行的落地方案。
>
> 本文只给结论与取舍；**字段级格式、切换交互与自动监控的实现细节见 [Token 多来源接入 —— 数据源格式与交互设计规格](../设计/Token多来源接入-设计规格.md)**。

## 0 结论速览

| 工具 | 额度（还剩多少） | token 用量（花了多少） | 本地数据是否真实可信 |
|------|------------------|------------------------|----------------------|
| DeepSeek Harness | 无（本机未接） | ✅ 已实现（zstd 会话 → SQLite 索引） | 是（本机抽样 5055 条 usage，totalTokens 与四桶之和 100% 一致） |
| Claude Code | ✅ 已实现（`/api/oauth/usage`） | ✅ 可做：`~/.claude/projects/**/*.jsonl` 的 `message.usage` | 是，但**一条 API 响应会拆成多行重复同一 usage**，不去重会虚高约 2.6 倍 |
| Codex CLI | ✅ 已实现（`chatgpt.com/backend-api/wham/usage`） | ✅ 可做：`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` 的 `event_msg/token_count` | 是，但 `cached_input_tokens` 是 `input_tokens` 的**子集**，口径必须换算 |
| Cursor | ✅ 已实现（`cursor.com/api/usage-summary`） | ⚠️ 只有一处**上下文快照**，没有逐轮累计 | 否：`bubbleId:*` 的 `tokenCount` 在当前版本恒为 0；缓存命中恒 0；社区实现按「字符数 ÷ 4」估算 |
| Gemini CLI | 无 | ✅ 可做：`~/.gemini/tmp/<project>/chats/session-*.jsonl` 的 `tokens` | 是，但**默认只保留 30 天且自动删除** |
| GitHub Copilot CLI | 无 | ✅ 可做：`~/.copilot/session-store.db` 的 `assistant_usage_events` 表 | 是（每请求一行，带真实时间戳） |
| OpenCode | ✅ 已有 opencode-go 额度 | ✅ 可做：`~/.local/share/opencode/opencode.db` 的 `message.data.tokens` | 是（三代存储并存，读 SQLite 即可） |
| Zed | 无 | ✅ 可做：`~/Library/Application Support/Zed/threads/threads.db`（`data` 为 zstd JSON） | 是，但无逐请求时间戳、无项目维度 |

三句话：

1. **额度与用量是两条链路，现状并不在同一水平线上**：额度侧已经覆盖 9 个 provider（Claude / Codex / Cursor 都在内），缺的是 Token 页的「多来源」。
2. **Claude Code 与 Codex CLI 是唯一两家「本地就有真实 token 数、格式稳定、有多个独立实现对得上」的来源**，应作为第一批。
3. **Cursor 只能停在额度**：它不在本地记录 token，强行接入只能给估算值，与现有精确口径混在一张表里会把「花了多少 token」这件事变成假的。

## 1 现状：额度与用量是两条线

### 1.1 额度线（Billing，已具备）

`Sources/NetworkMonitorCore/Billing/Providers/` 下已有 Claude / Codex / Cursor 三家的解码器，端点都是**非公开接口**：

| provider | 端点 | 来源标注 |
|----------|------|----------|
| Claude | `GET https://api.anthropic.com/api/oauth/usage` | [ClaudeBillingModels.swift:35](../../NetworkMonitor/Sources/NetworkMonitorCore/Billing/Providers/ClaudeBillingModels.swift#L35) 注「非公开端点」，形态来自社区 CodexBar |
| Codex | `GET https://chatgpt.com/backend-api/wham/usage` | [CodexBillingModels.swift:38](../../NetworkMonitor/Sources/NetworkMonitorCore/Billing/Providers/CodexBillingModels.swift#L38) 注「非公开端点」，形态来自 openai/codex 的 OpenAPI 模型 |
| Cursor | `GET https://cursor.com/api/usage-summary` | [CursorBillingModels.swift:41](../../NetworkMonitor/Sources/NetworkMonitorCore/Billing/Providers/CursorBillingModels.swift#L41) 注「非公开端点」 |

额度线的固有上限：它只能回答「某个窗口用了百分之几」，回答不了「我这一天烧了多少 token、花在哪个模型上、缓存命中多少」。后者才是 Token 页在做的事。

### 1.2 用量线（Token，目前只有 DSH）

- 数据源发现：`HarnessSourceDirectory`（显式偏好 > `DSH_HOME` > `~/.dsh/sessions`）— [HarnessSourceDirectory.swift](../../NetworkMonitor/Sources/NetworkMonitorCore/Harness/HarnessSourceDirectory.swift)
- 逐行解析：`HarnessEventParser.parse(line:)`，只认 `session` 与 `assistant/message` — [HarnessEventParser.swift](../../NetworkMonitor/Sources/NetworkMonitorCore/Harness/HarnessEventParser.swift)
- 落库：`harness_token_event(session_id, cwd, provider, model, ts_ms, uncached_in, output, cache_read, cache_write)` + `harness_session_scan(path, size, mtime_ms)` — [HarnessUsageIndexStore.swift](../../NetworkMonitor/Sources/NetworkMonitorCore/Harness/HarnessUsageIndexStore.swift)
- 增量：按 `(size, mtime)` 判重扫；同会话多版本文件按**事件内容**去重取并集 — [HarnessSessionScanner.swift](../../NetworkMonitor/Sources/NetworkMonitorCore/Harness/HarnessSessionScanner.swift)

**这套结构其实已经是一个「多来源就绪」的形态**：表里本来就有 `provider` 列，`HarnessTokenUsage` 也已经把四桶分开了。缺的不是重构，而是「第二个、第三个解析器」。

### 1.3 一个容易被忽略的优势：本地 transcript 会被上游清理

Claude Code 会 prune 旧 transcript，其自带的 `~/.claude/stats-cache.json` 也会冻结在某个日期上（clauth 的实现文档明确写了这两点，并因此自建 `token_ledger.json`）。这意味着**只扫文件、不沉淀，历史一定会丢**。

本项目的 Token 索引（`harness_token_event`）天然就是这份 ledger，把它扩展到多来源，比任何「每次重算磁盘」的第三方实现都更稳。这是接入其它 agent 的正确底座，不要改成实时全量扫描。

## 2 逐家数据源

### 2.1 Claude Code

**位置**（macOS）：

```text
~/.claude/projects/<sanitized-cwd>/<sessionId>.jsonl          # 旧：扁平
~/.claude/projects/<sanitized-cwd>/<sessionId>/<file>.jsonl   # 新：嵌套
~/.config/claude/projects/…                                   # 另一默认根
```

`CLAUDE_CONFIG_DIR` 可指定一个或多个（逗号分隔）根目录，多根数据合并统计。

**逐行结构**（每行一个 JSON 对象）：

```json
{"type":"assistant","sessionId":"…","cwd":"/Users/u/proj","gitBranch":"main",
 "timestamp":"2026-05-13T05:17:57.966Z","isSidechain":false,"isMeta":false,
 "requestId":"req_…",
 "message":{"id":"msg_…","model":"claude-opus-4-7",
   "usage":{"input_tokens":6,"cache_creation_input_tokens":14948,
            "cache_read_input_tokens":22745,"output_tokens":293}}}
```

事件类型：`user` / `assistant` / `system` / `attachment` / `file-history-snapshot` 与若干元数据行（`last-prompt`、`ai-title`、`pr-link`、`queue-operation`、`permission-mode`、`mode`），只有 `assistant` 带用量。

**三个必须处理的坑**：

1. **同一响应被拆成多行**：一条 API 消息的每个 content block 各占一行，`message.id` 与 `usage` 完全重复。实测样本 7166 行 assistant 塌缩到 2708 个唯一 id（不去重 ≈ 2.6 倍虚高），且 4458 条重复行的 usage 逐字节相同。→ 按 `message.id`（per session）去重。
2. **sidechain / subagent 重放**：`isSidechain: true` 的行会重放父会话消息——同一个 `message.id` 但不同 `requestId`，连父会话的 cache-read 用量一起带过来。ccusage 的处置是「保留父条目、丢弃 sidechain 副本」，且日汇总层的匹配不要求时间戳对齐。
3. **去重键分两档**：有 `requestId` 时按（message id, requestId）跨会话去重（Claude Code 会把同一响应复制进多个会话文件）；没有 `requestId` 时按（message id, 会话 id, timestamp）。

**口径**：Anthropic 的 `input_tokens` **不含**缓存部分，四桶互斥——和 DSH 一致，可以直接映射。

### 2.2 Codex CLI

**位置**：

```text
$CODEX_HOME（默认 ~/.codex）/
  sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl
  archived_sessions/YYYY/MM/DD/rollout-*.jsonl   # 归档副本，同一会话可能两处都有
  history.jsonl                                  # 只有 prompt 历史，无用量
```

**行包封**（新版 ≥ 约 0.44）：`{"timestamp": ISO8601, "type": T, "payload": {…}}`，T ∈
`session_meta`（首行，含 `id`/`cwd`/`cli_version`/fork 来源）、`turn_context`（`model` 的规范来源）、`response_item`、`event_msg`、`compacted`。

**用量只在** `event_msg` 且 `payload.type == "token_count"`：

```json
{"type":"event_msg","payload":{"type":"token_count","info":{
  "last_token_usage":{"input_tokens":1000,"cached_input_tokens":250,
    "output_tokens":125,"reasoning_output_tokens":75,"total_tokens":1200},
  "total_token_usage":{ "…同上形状，累计值…":0},
  "model_context_window":272000}}}
```

**四条记账规则**：

- 优先用 `last_token_usage`（当轮）。老文件只有累计的 `total_token_usage`，此时按字段做**差分**，并与上一次快照比对。
- `cached_input_tokens` 是 `input_tokens` 的**子集**（不是并列的第四桶）；极老的条目拼作 `cache_read_input_tokens`。换算：`uncachedInput = input - cached`，`cacheRead = cached`。
- `reasoning_output_tokens` **已包含在** `output_tokens` 里，不要再加。
- 累计计数会**回退**（compaction / fork / 陈旧快照）：回退时重设基线、不记负数。

**另两条**：`info` 可能为 `null`（跳过该行）；fork 会话会在文件开头**重放父会话的 token_count 行**，其时间戳早于本会话 `session_meta`，据此跳过。2025-09-06 之前的版本根本没有 token 遥测。

**额度侧补充**：`rate_limits` 也会写进 rollout 文件（`turn_context` 附近），可作离线兜底。

### 2.3 Cursor

**本地有什么**：

- `~/.cursor/projects/<workspace>/agent-transcripts/<id>/<id>.jsonl`：消息与工具调用，**没有 token 字段**（Cursor 官方论坛 2026-10 已有人提特性请求，原话是 "These files have the messages and tool calls, but no token usage"）。
- `~/.cursor/chats/<hash>/<agentId>/store.db`：blob 存储，同样不带 token。
- `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`：IDE 侧状态，**不是单表**——`cursorDiskKV`（`bubbleId:<composerId>:<uuid>` / `composerData:` / `agentKv:blob:*`）与 `ItemTable`（`cursorAuth/accessToken`、`composer.composerData`，新版改名 `composer.composerHeaders` 落在 workspace 级）分工不同。

**本地能拿到的那一点点**：

- `bubbleId:*` 的 `tokenCount.inputTokens/outputTokens` **仅旧版有值**，当前构建恒为 `{0,0}`。
- 唯一带真实数字的是上下文快照 `composerData.promptTokenBreakdown.totalUsedTokens`（回退 `contextTokensUsed`）——它是**某次上下文占用**，不是逐轮累计，也不能按天求和。
- 缓存命中在本地恒为 0。

**第三方怎么处理**：成熟实现（codeburn）明确写「transcripts and store.db record no token counts」，于是用 `CHARS_PER_TOKEN = 4` 从字符数**估算**，并对每次调用标记 `costIsEstimated`。

**真实值只有服务端**：`GET cursor.com/api/usage-summary`（只给额度/美元）与 `GET cursor.com/api/dashboard/export-usage-events-csv?startDate=…&endDate=…&strategy=tokens`（CSV 含 Input / Cache Read / Output 列），团队另走 `POST api.cursor.com/teams/filtered-usage-events`。认证是 Cookie `WorkosCursorSessionToken=<user>::<jwt>`；3.27 起本地存 `cursor-safe-storage:v1:` 加密串，需钥匙串项 `Cursor Safe Storage` 解密（读时会弹系统授权），JWT `exp` 到期即失效、须重登。

**本项目结论**：Cursor 停在额度线。若日后要接，只能是「官方导出 / 接口」这一条路，且必须与精确来源在 UI 上区分标记，不能混算。

### 2.4 Gemini CLI / Copilot CLI / OpenCode（第二批候选）

| 工具 | 位置 | 字段与坑 |
|------|------|----------|
| Gemini CLI | `$GEMINI_CLI_HOME/.gemini`（默认 `~/.gemini`）→ `tmp/<项目 slug>/chats/session-<UTC>-<8位>.jsonl`；旧版是 `session-*.json`，旧桶名是 project root 的 sha256 | 记录 `type:"gemini"` 上的 `tokens{input,output,cached,thoughts,tool,total}`，源码映射 `input=promptTokenCount` / `output=candidatesTokenCount` / `cached=cachedContentTokenCount` / `thoughts=thoughtsTokenCount`；`tokens` 可能为 null；迁移会复制旧桶导致双份；`$set.messages` 全量重写需去重；**默认保留 30 天自动删** |
| Copilot CLI | `~/.copilot/session-store.db`（SQLite，WAL） | 表 `assistant_usage_events`：每请求一行，`input_tokens` 是 **cache-inclusive**（与 Codex 同口径），另有 cache read / write、reasoning、模型、**真实请求时间戳**；`session-state/<id>/events.jsonl` 只在干净退出时写 rollup |
| OpenCode | `~/.local/share/opencode/opencode.db`（SQLite，WAL） | `message.data.tokens = {total, input, output, reasoning, cache:{read,write}}`；`tokens.reasoning` 与 `output` 分开（要相加）；`session` 表有 `directory`、`cost`、`tokens_input/tokens_output`；旧版是 `storage/` JSON 树，三代格式并存 |
| Zed | `~/Library/Application Support/Zed/threads/threads.db` | 表 `threads(id, summary, updated_at, data)`，`data` 是 **zstd 压缩的 JSON**，含 `request_token_usage`（按用户消息 id → input / output / cache_creation / cache_read）与 `cumulative_token_usage`、`model.{provider,model}`；**无逐请求时间戳**（只能用 thread `updated_at`）、项目维度未映射 |

另两家需要排掉：**Aider** 默认不落盘，只有用户手动加 `--analytics-log` 才有 `analytics.jsonl`（且无缓存字段，不可依赖）；**Cursor** 见 2.3。

OpenCode / Copilot / Zed 都要**只读打开**（`mode=ro` + `PRAGMA query_only`），CLI 可能正持有该文件；Zed 的 `data` 列还要过 zstd 解压（本项目已有 `HarnessZstdDecoder` 可复用）。

### 2.5 DSH 现状实测校验（本机真实数据）

顺手把现有解析器拿真实数据校了一遍（只统计类型与字段名，未读正文；首批 40 个会话 / 27478 行做事件类型普查，60 个会话做口径核对）：

| 观察项 | 实测结果 | 对现有实现的意义 |
|--------|----------|------------------|
| `assistant/message` 里 `data.message.source` | 2822/2822 行都带 `kind/model/provider/replayState` | 现有取 provider/model 的方式正确 |
| `usage` 键 | `inputTokens`/`outputTokens`/`totalTokens`/`cacheReadTokens`（`cacheWriteTokens` 0 次） | 读缺失桶按 0 兜底，无害 |
| `totalTokens` vs 四桶之和 | 5055/5055 完全相等 | 口径自洽，没有隐藏的第五桶 |
| `assistant/attempt` | 345 条，**全部不带 usage**（只有 `turn`/`step`/`stream`） | 不解析它是对的，没有漏算 |
| `request/header` | 66 条，`data = {header, reason}` | 未解析亦不影响（provider/model 已在 message.source） |
| `session/end-seed` / `compaction/summary` | 样本 0 次 | **潜在缺口**：ccusage 的 dsh adapter 会读这两类（fork 继承历史、压缩摘要自带 usage），本机样本尚未触发，需要在 fork 会话上补验 |

结论：现有 DSH 解析在本机数据上是准的，可作为复用到其它来源的范式；唯一待补的是 fork/compat 两类稀疏事件。

## 3 口径对齐（实现阶段最容易翻车的地方）

四桶统一到 `HarnessTokenUsage(uncachedInput, output, cacheRead, cacheWrite)`：

| 来源 | uncachedInput | output | cacheRead | cacheWrite |
|------|---------------|--------|-----------|------------|
| DSH | `inputTokens` | `outputTokens` | `cacheReadTokens` | `cacheWriteTokens` |
| Claude Code | `input_tokens` | `output_tokens` | `cache_read_input_tokens` | `cache_creation_input_tokens` |
| Codex | `input_tokens - cached_input_tokens` | `output_tokens`（含 reasoning） | `cached_input_tokens` | 无（恒 0） |
| Gemini CLI | `input - cached` | `output + thoughts` | `cached` | 无 |
| Copilot CLI | `input_tokens - (cache read)` | `output_tokens`（reasoning 单列） | cache read | cache write |
| OpenCode | `input` | `output + reasoning` | `cache.read` | `cache.write` |
| Zed | `input_tokens` | `output_tokens` | `cache_read_input_tokens` | `cache_creation_input_tokens` |

三条硬规则：

1. **「input 是否含 cache」是分水岭**：DSH / Anthropic 互斥，OpenAI / Gemini 包含。混用会让缓存命中率算成负数或超过 100%。
2. **输出侧的 reasoning 只加一次**：Codex 已包含，OpenCode / Gemini 单列。
3. **时间戳统一到 epoch ms**（现有实现即为 ms），再按项目固定口径 Asia/Shanghai 分天。

## 4 落地方案

### 4.1 抽象：把「只有 DSH」拆成一个来源协议

现状里 DSH 的耦合点只有两处：发现文件（`HarnessSessionScanner`）与解析行（`HarnessEventParser` 的 `switch root["type"]`）。做法：

```text
TokenSourceID（dsh / claude-code / codex / gemini / copilot / opencode）
  ├─ 发现：roots（含环境变量 + 显式偏好）、文件 glob、是否压缩、归档目录去重
  ├─ 解析：parse(line) -> TokenUsageEvent?（统一四桶 + ts + model + provider + sessionKey）
  └─ 诊断：目录缺失 / 不可读 / 版本过旧（无遥测） 各成一类，别混成空态
```

要点：

- **不要**给每个来源建一张表：`harness_token_event` 加一列 `source`（带默认值迁移），扫描账本 `harness_session_scan` 的 `path` 已是全局唯一，天然可以跨来源。
- 解析器保持**纯函数**（现有 `HarnessEventParser` 就是），一行坏掉只计数，绝不整文件失败。
- 去重键按来源给：DSH 用事件内容；Claude 用 `message.id`（+ requestId / 会话 id 视有无而定）；Codex 用「累计差分」本身即天然去重（同一文件顺序读）。

### 4.2 三个来源的解析口径（实现时的验收线）

| 来源 | 单测必须覆盖 |
|------|--------------|
| Claude Code | 同一 `message.id` 多行只算一次；`isSidechain` 副本丢弃；无 `requestId` 时的三元组去重；坏行不影响 |
| Codex | `last_token_usage` 优先；只有累计时差分正确；累计**回退**不记负数；`input` 含 cached 的换算；fork 重放行被跳过 |
| 通用 | 时间戳缺失 → 跳过并计数；`info: null` → 跳过 |

### 4.3 UI 影响（比解析本身更费工）

- **设置页 / Token 段**：从「一个目录偏好」变成「数据源清单」——每家一行：是否已安装（目录存在）、路径与来源、已索引会话/事件数、最近扫描时间、单独「重新扫描」。
- **Token 页**：屏与二级页的分母/口径不变（本文件写作时还是 4 屏，现行为 2 屏：总览 / 分布），但增加「来源」维度——总览的四族卡与分布屏可以加一档「按工具」，或在图例里按来源着色。
- **不可用态**：沿用现有的「缺失 / 不可读 / 缺工具」三分，每家各自报自己的原因，不能合并成一句「暂无数据」。

### 4.4 分阶段

1. **P1**：抽象 TokenSource + Claude Code / Codex CLI 两个解析器 + `source` 列迁移 + 设置页数据源清单。两家都有多个独立第三方实现对得上，且本机可造 fixture。
2. **P2**：Copilot CLI（`assistant_usage_events` 每请求一行、带真实时间戳，质量最高）、Gemini CLI、OpenCode、Zed（三者都只读 SQLite / zstd）。
3. **P3**：Cursor——只在额度侧完善，不接 token；若将来官方开放导出，再做一条「导入」通道（明确标记来源为导入，不与本地扫描混算）。

## 5 风险与不做清单

| 风险 | 说明与对策 |
|------|------------|
| 格式漂移 | 三家的格式说明都是「观察所得，不是契约」。解析必须防御式：字段缺失即按 0/跳过，坏行计数在诊断里可见 |
| 隐私 | transcript 含**完整对话正文**。只读 usage 字段，正文不落库、不进日志（沿用 `LogRedaction` 纪律）；设置页不展示样本行 |
| 性能 | Claude 单文件可到 20MB+，Codex 一年几百 MB。必须走现有 `(size, mtime)` 增量，禁止每次全量 |
| 上游清理 | 见 1.3：索引即账本，不能改成「每次重算磁盘」 |
| 时间口径 | 三家时间戳形态不同（ISO8601 Z / epoch s / epoch ms），统一到 ms 后再分天 |
| **不做** | Cursor 本地估算 token（与精确来源混算会污染整个页面）；依赖 Cookie / 私有接口抓取 Cursor 用量（认证随时失效、属未公开契约，与现有额度实现同风险但收益更低）；Aider（默认不落盘，需用户手动开 opt-in） |

## 6 待验证（需要真机装工具）

1. 本机未安装 `claude` / `codex` / `cursor` / `gemini`，所有格式结论来自公开解析器与上游源码笔记，**未在本机实证**。接入前需各装一个、跑一段真实会话、用 fixture 固化样本。
2. Claude Code `~/.claude/stats-cache.json` 的字段（`dailyActivity` / `modelUsage` / `hourCounts`）可用于「日级快速汇总」，但它会冻结、老数据无缓存拆分，且缺字段在全新安装上很常见——只宜作对照，不宜作主路径。
3. Cursor 新版本是否已把 token 写进 transcript（论坛请求可能已被采纳），或 `bubbleId.tokenCount` 是否恢复有值；每次改版前重验一次。
4. DSH 的 `session/end-seed`（fork 继承历史）与 `compaction/summary` 在本机样本中未出现，需要构造 fork 会话验证是否重复计数。
5. Gemini CLI 与 Zed 都有「上游会自动删」的性质（Gemini 默认 30 天），意味着**接进来之后必须尽快沉淀进 SQLite 索引**，晚接入就会永久缺一段历史。

## 7 证据源

- Claude Code transcript 结构与去重：<https://raw.githubusercontent.com/repowise-dev/skiplevel/refs/heads/main/docs/schema-notes.md>
- Claude Code 数据目录 / `CLAUDE_CONFIG_DIR` / sidechain 去重口径：<https://github.com/ccusage/ccusage/blob/main/rust/adapters/claude/src/README.md>
- Claude Code 统计行数与唯一 id 实测（2.6 倍虚高）：同上 schema-notes
- Claude Code transcript 被 prune、stats-cache 冻结、需自建 ledger：<https://github.com/uwuclxdy/clauth/blob/main/wiki/Tokens-And-Cost.md>
- Codex rollout 格式与 token 记账规则：<https://raw.githubusercontent.com/repowise-dev/skiplevel/refs/heads/main/docs/schema-notes-codex.md>
- Cursor 本地 transcript 无 token（官方论坛特性请求）：<https://forum.cursor.com/t/record-token-usage-in-local-agent-transcripts/175149>
- Cursor 估算口径与 IDE/CLI 记账边界：<https://github.com/getagentseal/codeburn/blob/main/docs/providers/cursor-agent.md>
- Gemini CLI 字段映射（源码级）：<https://github.com/google-gemini/gemini-cli/blob/main/packages/core/src/services/chatRecordingTypes.ts>
- Gemini CLI 会话格式：<https://github.com/getagentseal/codeburn/blob/main/docs/providers/gemini.md>
- Copilot CLI `session-store.db` 与 `assistant_usage_events`：<https://github.com/getagentseal/codeburn/blob/main/docs/providers/copilot.md>
- Copilot CLI 本地遥测（无历史聚合）：<https://pypi.org/project/copilot-token-tracker/>
- Cursor 的 `state.vscdb` 表结构与 `tokenCount` 恒零：<https://github.com/getagentseal/codeburn/blob/main/src/providers/cursor.ts>
- Cursor 用量导出与认证形态：<https://github.com/getagentseal/codeburn/blob/main/docs/providers/cursor.md>
- Zed `threads.db` 结构：<https://github.com/getagentseal/codeburn/blob/main/docs/providers/zed.md>
- Aider 仅在 opt-in 时落盘：<https://github.com/Aider-AI/aider/blob/main/aider/analytics.py>
- OpenCode 三代存储与 `tokens` 字段：<https://raw.githubusercontent.com/repowise-dev/skiplevel/refs/heads/main/docs/schema-notes-opencode.md>
- DSH adapter 的事件覆盖（含 `session/end-seed` / `compaction/summary`）：<https://github.com/ccusage/ccusage/blob/main/rust/adapters/dsh/README.md>
