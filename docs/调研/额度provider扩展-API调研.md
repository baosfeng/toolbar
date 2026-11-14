# 额度 provider 扩展（Cursor / Codex / Claude）与多实例 API 调研

> 调研范围：额度页新增 Cursor、Codex（OpenAI）、Claude（Anthropic）三类 provider，并支持同一 provider 多实例；配套「额度恢复通知」所需信号。
> 所有代码事实带 `文件:行号`；所有外部接口带证据 URL 与「公开 / 非公开」标注。
> 本文只做调研与设计，不含实现；实现按编码规范 `.agents/skills/toolbar-coding-standards/SKILL.md` 执行。

---

## 0 结论速览

| provider | 推荐端点（首选） | 认证 | 公开性 | 能给出的额度信号 |
|---|---|---|---|---|
| Claude（订阅额度） | `GET https://api.anthropic.com/api/oauth/usage` | OAuth access token（`Bearer` + `anthropic-beta: oauth-2025-04-20`） | **非公开端点**（社区实证，可能失效） | 5 小时窗口 / 周窗口 / 模型专属周窗口的 `utilization` + `resets_at` |
| Claude（组织用量） | `GET https://api.anthropic.com/v1/organizations/usage_report/messages`、`/v1/organizations/cost_report` | Admin Key `sk-ant-admin…`（`x-api-key` 或 `Bearer`） | **公开官方 API** | 组织级 token / 消息 / 金额（日桶），不是订阅窗口额度 |
| Codex（订阅额度） | `GET https://chatgpt.com/backend-api/wham/usage` | ChatGPT OAuth token（`~/.codex/auth.json` 的 access token，`Bearer`） | **非公开端点**（openai/codex 客户端自用，可能失效） | `primary_window`（5h）/`secondary_window`（周）的 `used_percent`、`reset_at`、`limit_window_seconds` |
| Codex（组织用量） | `GET https://api.openai.com/v1/organization/usage/completions`、`/v1/organization/costs` | Admin Key（`Authorization: Bearer`，需 Admin 权限） | **公开官方 API** | token / 请求数 / 金额（`1d` 桶，`costs` 仅 `1d`） |
| Cursor（个人订阅额度） | `GET https://cursor.com/api/usage-summary` | Cookie `WorkosCursorSessionToken`（或 Cursor.app 的 `cursorAuth/accessToken` JWT） | **非公开端点**（dashboard 前端接口，可能失效） | 计划额度已用 / 上限、`billingCycleStart/End`、on-demand 用量 |
| Cursor（团队/组织用量） | `POST https://api.cursor.com/organizations/spend`、`/organizations/daily-usage-data`、`/organizations/pooled-usage` | Basic auth，API Key 作用户名，scope `usage:*` | **公开官方 API** | 成员/团队级用量与花费（需要团队或组织管理员 Key） |

一句话取舍：**三个 provider 都能同时提供「官方组织用量（稳，但只覆盖 API 花费）」与「订阅窗口额度（准，但是非公开端点）」**。额度页要的是「订阅窗口剩余百分比 + 重置时间」，所以三家的主路径都落在非公开端点上；官方 API 作为「有 Admin Key 时的高可信回退/叠加」。这决定了新 provider 要显式标注「可能失效」，并在解析失败时退化为一条可自愈的提示，而不是整块空白。

---

## 1 现有额度架构事实

### 1.1 Core 契约（`Sources/NetworkMonitorCore/Billing/`）

**`BillingProvider.swift`**

- 协议 `BillingProvider: Sendable`（`:9-44`），成员逐个：
  - `var id: String`（`:11`）——注释原文「稳定标识（凭据存储键、持久化偏好都用它，发布后不可变更）」→ **这是多实例改造的核心冲突点**：协议把「provider 类型」与「凭据键」绑成了同一个字符串。
  - `displayName`（`:13`）、`symbolName`（`:15`）、`supportsModelBreakdown`（`:17`）、`supportsTimeSeries`（`:19`）、`supportsUsage`（`:21`）、`supportedUsageRanges`（`:26`）、`minimumRefreshInterval`（`:31`）、`credentialHint`（`:33`）、`credentialPageURL`（`:35`）、`environmentCredentialKey`（`:37`）。
  - `func fetchBalance(credential: String) async throws -> BillingBalance`（`:40`）
  - `func fetchUsage(range: BillingRange, credential: String) async throws -> BillingUsage`（`:43`）
  - **凭据就是一个 `String`**，没有「凭据种类」维度（API Key / Cookie / OAuth token 全部塞进同一个字段）。
- `BillingError`（`:47-86`）：`missingCredential / unauthorized / forbidden(String?) / rateLimited(retryAfter:) / serviceUnavailable / invalidRequest / invalidResponse / transport`，`userMessage` 直接给中文（`:66-85`）。
- `BillingProviderRegistry`（`:93-127`）：`register` 按 id 覆盖（`:106-111` `providers.removeAll { $0.id == provider.id }`）、`all`（`:114-118`）、`provider(id:)`（`:121-123`）、`isEmpty`（`:126`）。→ **注册表天然「同 id 唯一」，这就是「同一 provider 只能有一份配置」的第二道锁。**
- 协议默认实现 `:131-151`，其中 `environmentCredentialKey` 默认 `BILLING_<ID 大写、连字符转下划线>_API_KEY`（`:148-150`）。

**`BillingModels.swift`**

- `BillingRange`（`:6-22`）：`last24Hours/last7Days/last30Days`。
- `BillingPeriod`（`:33-57`）：`start/end`、`duration`、`progress(at:)`、`remainingDays(at:)`。
- `BillingIncludedBalance`（`:60-79`）：`remainingUSD / allowanceUSD / period`；`remainingFraction`（`:75-78`）。
- `BillingPercentLimit`（`:82-115`）：`id / title / remainingFraction / resetsAt / usedAmount / limitAmount / unitLabel / badge` + `hasAmountDetail`（`:114`）。**这是新 provider 落订阅窗口的主力结构**——已有 `resetsAt` 与 `badge`，但**没有「窗口种类/窗口时长」**。
- `BillingBalance`（`:118-144`）：`included / purchasedUSD / percentLimits`、`totalAvailableUSD`、`isEmpty`。
- 用量侧 `BillingMetrics`（`:149-167`）、`BillingGroup`（`:170-179`）、`BillingBucket`（`:182-198`）、`BillingUsage`（`:201-225`）。

**`BillingCredentialStore.swift`**

- 协议 `BillingCredentialStore`（`:51-58`）：`credential(for providerID:)` / `setCredential(_:for:)` / `credentialResolution(for:)`。**参数名就是 `providerID`**，语义上「一个 provider 一条」。
- `BillingCredentialSource`（`:14-21`）：`stored / environment / none`；`BillingCredentialResolution`（`:24-44`）：`credential / source / storageKey / environmentKeys / isConfigured`。
- `PreferencesBillingCredentialStore`（`:83-113`）：偏好存储 + `EncryptedSecretStore`（AES-GCM，`:109`）。
  - `storageKey(for:)` = `"billing.credential." + providerID`（`:116-118`）——**键空间本身已支持任意字符串 id，多实例不需要换格式**。
  - `credentialResolution`（`:148-165`）：存储优先、环境变量仅回退，绝不合并。
  - `setCredential`（`:177-187`）：先清偏好旧明文，再写秘密存储。
  - `migrateLegacyPlaintext(for providerIDs:)`（`:194-206`）：启动时按注册表全量搬迁。
- 头注释 `:5-13` 把「同一 provider 只有一条生效凭据」写成了显式契约（注释里点名「用户反馈『同一个 provider 不支持重复配置』的落地口径」）——**多实例改造要同时改写这段契约与对应单测**。

**`BillingProviderPreferences.swift`**

- `keyPrefix = "billing.enabled."`（`:15`）；`storageKey(for:)` = 前缀 + providerID（`:24-26`）；`isEnabled` 缺省为开（`:29-33`）；`setEnabled`（`:36-38`）；纯函数 `filterEnabled`（`:51-54`）。→ 启用开关同样是**按 id 一维**。

**`BillingRefreshScheduler.swift`**

- 全局下限 `minimumInterval = 60`（`:15`）；`interval(providerMinimum:)`（`:21-23`）取较大者；`isDue(now:lastAttempt:providerMinimum:force:)`（`:32-37`）。→ 节流按 providerID 各自计时，多实例天然各自独立。

**`BillingVisibility.swift`**：`isVisibleInCredits(isConfigured:isEnabled:)`（`:23-25`）、`visibleEntries`（`:34-38`）、`isEmptyState`（`:44`）。→ 泛型过滤，不绑定 id 语义，多实例零改动。

**`BillingAlerts.swift`**：见 §4.1。

### 1.2 可执行目标（`Sources/NetworkMonitor/Billing/`）

**`BillingMonitor.swift`**（`@MainActor final class`，`:15-337`）

- 依赖：`registry`（`:20`）、`credentialStore`（`:22`）、`preferences`（`:24`）、`alertService`（`:26`）。
- 状态：`states: [ProviderState]`（`:33`）、`generations: [String: Int]`（`:35`）、`lastAttempts: [String: Date]`（`:37`）——**全部以 `descriptor.id` 为键**。
- `init(registry:credentialStore:alertService:preferences:logger:)`（`:58-74`）：`:68-70` 用 `preferences.isEnabled($0.id)` 过滤后 `map(Self.makeState)`。
- `refresh(force:)`（`:81-105`）、`selectRange(_:providerID:)`（`:108-150`）、`pause/resume`（`:158-174`）、`saveCredential(_:providerID:)`（`:179-194`）、`clearCredential(providerID:)`（`:197-210`）、`startLoad`（`:218-244`）、`apply(results:targets:)`（`:247-299`，`:263-266` 调 `alertService?.handle(balance:providerID:providerName:)`）、`nextGeneration`（`:318-322`）、`emit()`（`:333-336`）。
- 结论：**只要 `descriptor.id` 唯一，整个状态机对「多实例」是透明的**。

**`BillingMonitor+Fetching.swift`**：`FetchTarget`（`:15-26`）、`collectFetchTargets(now:force:)`（`:32-52`，`:37` `registry.provider(id: id)`、`:38` `credentialStore.credential(for: id)`）、`BillingOutcome`（`:57-60`）、`fetchBalance/fetchUsage`（`:63-89`）。

**`BillingMonitor+Providers.swift`**：`setProviderEnabled(_:providerID:)`（`:16-29`）、`makeState(for:credentialStore:)`（`:32-51`）、`rebuildStates()`（`:54-67`，`:57` `BillingProviderPreferences.filterEnabled(registry.all.map { $0.id })`）。

**`BillingMonitorSnapshot.swift`**：`ProviderDescriptor`（`:13-48`，字段 `id/displayName/symbolName/credentialHint/supportsModelBreakdown/supportsTimeSeries/supportsUsage/supportedRanges/credentialPageURL`）、`ProviderState`（`:50-67`）、`Snapshot`（`:75-117`，`:93-95` `state(for:)` 按 `descriptor.id`）、`ProviderFetchResult`（`:128-133`）。

**组合根 `AppCoordinator.swift:110-129`**

```swift
let billingRegistry = BillingProviderRegistry(providers: [
    OllamaBillingProvider(logger: logger),
    OpenDesignBillingProvider(logger: logger),
    OpencodeGoBillingProvider(logger: logger),
])
let billingCredentials = PreferencesBillingCredentialStore(
    environmentKeyResolver: { providerID in
        billingRegistry.provider(id: providerID)?.environmentCredentialKey
            ?? PreferencesBillingCredentialStore.defaultEnvironmentKey(for: providerID)
    })
billingCredentials.migrateLegacyPlaintext(for: billingRegistry.all.map(\.id))
let billingAlerts = BillingAlertService(storage: AppContext.shared.storage, logger: logger)
let billingMonitor = BillingMonitor(registry: billingRegistry, credentialStore: billingCredentials,
                                    alertService: billingAlerts, logger: logger)
```

**设置页 `SettingsProvidersPane.swift`**：`private var rows: [String: ProviderRowView]`（`:33`）、`buildContent` 遍历 `monitor.registry.all` 建行（`:53-72`）、`refresh()` 按 `provider.id` 取 `credentialResolution`（`:94-111`）、`save(_:providerID:)`（`:136-154`）、`setRowsLocked(except:locked:)`（`:166-170`）；页脚文案写死「每个 Provider 只保留一份 Key（重复提交会覆盖）」（`:83-84`）。

### 1.3 现状锁：三处「一个 provider 一份配置」的硬约束

1. `AGENTS.md` 功能模块表：「额度 Provider（启用开关＝下线、行内凭据编辑、**同一 provider 只有一份凭据**、凭据以 AES-GCM 密文本地存储）」。
2. `BillingCredentialStore.swift:5-13` 契约注释（唯一键 `billing.credential.<providerID>`、写入永远覆盖）。
3. 单测 `BillingVisibilityTests.swift:51-102` `testSingleConfigurationContract()`：
   - `:56-61` 断言 `registry.all.count == 2`、同 id 唯一、「覆盖后移到末位」；
   - `:67-72` 断言重复写入是替换、秘密存储里「同一 provider 只有一条记录」（`secrets.values.count == 1`）；
   - `:93-101` 断言环境变量回退与来源标记。
   → **多实例必须改写这条测试的语义**（见 §3.5），否则编译期不红、测试期必红。

---

## 2 三家 provider 调研

### 2.1 Claude / Anthropic

#### 方案 A（推荐，订阅额度）：OAuth usage 端点

- 端点：`GET https://api.anthropic.com/api/oauth/usage?cedar_ember=1`
- 请求头（社区实现实测）：`Authorization: Bearer <access_token>`、`anthropic-beta: oauth-2025-04-20`；可选查询参数 `cedar_ember=1` 用于取「重置额度清单」，不支持时降级重试一次（去掉该参数）。
- 认证：**Claude Code 的 OAuth access token**（Keychain/配置文件里的 `claudeAiOauth`），需要 `user:profile` scope；只有 `user:inference` 的 token 调不动 usage。`claude setup-token` 产出的 token 是模型请求用，不能顶替。
- 返回字段（`OAuthUsageResponse` / `OAuthUsageWindow` / `OAuthExtraUsage`）：
  - `five_hour`：`{ utilization, resets_at }` —— 5 小时会话窗口；缺失或 null 表示无该窗口（Free 计划）。
  - `seven_day`：周窗口；`seven_day_oauth_apps` 作为回退。
  - `seven_day_sonnet` / `seven_day_opus`：模型专属周窗口；新形态在 `limits[].weekly_scoped`。
  - `seven_day_routines` / `seven_day_cowork`：附加窗口（Daily Routines）。
  - `extra_usage`：`{ is_enabled, monthly_limit, used_credits, utilization, currency }`。
  - 每个窗口的 `utilization` 是**已用百分比**（0–100），`resets_at` 是 ISO8601 字符串。
- 映射建议：`utilization/100` → `BillingPercentLimit.remainingFraction = 1 - used`；`resets_at` → `resetsAt`（与 `OpencodeGoBillingProvider.swift:97-116` 的换算范式一致：接口给已用、App 内统一存剩余、钳制 0…1）。
- 公开性：**非公开端点**（未出现在 Anthropic 官方 API 文档，由社区客户端逆向并使用），**可能随时失效**；HTTP 400/403 应重试一次（去掉 `cedar_ember`），401/429 按 `BillingError.unauthorized / .rateLimited` 处理。
- 证据：
  - 端点与头部、字段映射：<https://github.com/steipete/CodexBar/blob/main/docs/claude.md>（`:233-252`）
  - 字段定义（Swift DTO）：<https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthUsageFetcher.swift>（`:284-320` 键名、`:373-398` `OAuthUsageWindow`/`OAuthExtraUsage`）

#### 方案 A'（同为订阅额度，Web Cookie 版）

- 端点：`GET https://claude.ai/api/organizations` → `GET https://claude.ai/api/organizations/{orgId}/usage?cedar_ember=1`（同样给 session/weekly/opus 百分比 + 重置）；配套 `/overage_spend_limit`、`/prepaid/credits`、`/api/account`。
- 认证：Cookie `sessionKey=sk-ant-…`（浏览器登录态）。
- 公开性：**非公开端点**。
- 证据：<https://github.com/steipete/CodexBar/blob/main/docs/claude.md>（`:360-376`）

#### 方案 B（官方 API，组织用量/花费）

- 端点（legacy，仍受支持，需 raw HTTP）：`GET https://api.anthropic.com/v1/organizations/usage_report/messages`、`GET https://api.anthropic.com/v1/organizations/cost_report`。
  - 新版：`GET /v1/organizations/analytics/usage`、`GET /v1/organizations/analytics/cost`（需 `anthropic-beta: analytics-usage-cost-2026-08-24`，维度 `model/workspace_id/api_key_id/service_tier/product/actor`，时间桶 `1m/1h/1d`，返回 `data_refreshed_at`）。
- 认证：Admin API Key `sk-ant-admin…`（`x-api-key` 或 `authorization: Bearer`），或 `org:admin` OAuth token；`anthropic-version` 头必需。
- 关键限制：`usage_report/messages` 的 `bucket_width=1h/1m` 数据**滞后约 30 分钟**、当天桶只在该桶结束后出现；`cost_report` 是日粒度且止于最近一次 UTC 零点。→ **拿不到「当前 5 小时窗口还剩多少」**，只能做「今日/7 天/30 天花费」。
- 公开性：**公开官方 API**。
- 证据：
  - 官方文档（本机所在区域被地区限制拦下，仅能从检索结果确认 URL 存在）：<https://platform.claude.com/docs/en/api/admin/usage_report/retrieve_messages>
  - 官方文档镜像全文（含鉴权表、参数、限制）：<https://github.com/asgeirtj/system_prompts_leaks/blob/main/Anthropic/claude-code/skills/claude-api/shared/admin-api.md>（legacy 报告 `:184`、analytics 新端点 `:174-182`、鉴权表 `:7-21`）
  - 社区实现落地（`cost_report`/`usage_report` 双端点、`group_by[]=model`、`bucket_width=1d`）：<https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Claude/ClaudeAdminAPIUsageFetcher.swift>（`:27-29`、`:98-113`、`:253-254`、`:447-465`）

**建议**：Claude provider 主路径 = 方案 A（订阅窗口），`supportsUsage = false`（首版只查额度）；Admin Key 版本作为后续可选项（同一 provider 的第二个实例形态，正好验证多实例模型）。

### 2.2 Codex / OpenAI

#### 方案 A（推荐，订阅额度）：wham/usage

- 端点：`GET https://chatgpt.com/backend-api/wham/usage`
- 认证：ChatGPT 账号的 OAuth access token（Codex CLI 写在 `~/.codex/auth.json` 或 `$CODEX_HOME/auth.json`），`Authorization: Bearer <token>`；`$CODEX_HOME/config.toml` 的 `chatgpt_base_url` 可覆盖端点。
- 返回字段（以 openai/codex 仓库生成模型为准）：
  - 顶层 `plan_type`（plus/pro/…）、`rate_limit`、`credits`、`spend_control`、`additional_rate_limits[]`、`rate_limit_reached_type`。
  - `rate_limit.allowed` / `rate_limit.limit_reached`；
  - `rate_limit.primary_window` 与 `secondary_window`，每个窗口 `{ used_percent, limit_window_seconds, reset_after_seconds, reset_at }`。
  - `additional_rate_limits[]`：模型专属限额（如 GPT-5.3-Codex-Spark），映射为附加的 5 小时 / 周窗口。
  - 观测到的固定 30 天窗口：`limit_window_seconds == 2592000`。
- 映射建议：`primary_window`（`limit_window_seconds≈18000`，5 小时）与 `secondary_window`（`≈604800`，周）→ 两条 `BillingPercentLimit`（`id = "codex-session" / "codex-weekly"`）；`1 - used_percent/100` → `remainingFraction`；`reset_at`（epoch 秒）→ `resetsAt`。
- 公开性：**非公开端点**（ChatGPT 后端自用，非 OpenAI 公开 API），**可能失效**；端点失败时降级为一条提示。
- 证据：
  - 端点与映射说明：<https://github.com/steipete/CodexBar/blob/main/docs/codex.md>（`:58` 端点、`:72-75` 窗口映射与 30 天窗口、`:104` `additional_rate_limits[]`）
  - 响应模型（OpenAI 官方仓库，生成自 codex-backend OpenAPI）：`RateLimitStatusPayload` <https://github.com/openai/codex/blob/main/codex-rs/codex-backend-openapi-models/src/models/rate_limit_status_payload.rs>；`RateLimitWindowSnapshot`（`used_percent/limit_window_seconds/reset_after_seconds/reset_at`）<https://github.com/openai/codex/blob/main/codex-rs/codex-backend-openapi-models/src/models/rate_limit_window_snapshot.rs>；`RateLimitStatusDetails`（`allowed/limit_reached/primary_window/secondary_window`）<https://github.com/openai/codex/blob/main/codex-rs/codex-backend-openapi-models/src/models/rate_limit_status_details.rs>
  - 附：响应头同样携带配额（`x-codex-primary-used-percent` / `x-codex-secondary-window-minutes` / `x-codex-secondary-reset-at`），见 <https://github.com/openai/codex/blob/main/codex-rs/codex-api/src/rate_limits.rs>（`parse_rate_limit_for_limit`，`~:60-90`）

#### 方案 B（官方 API，组织用量/花费）

- 端点（公开 API 参考，`security: AdminApiKeyAuth` = http bearer）：
  - `GET https://api.openai.com/v1/organization/usage/completions`：`start_time`(必) / `end_time` / `bucket_width`(支持 `1m`/`1h`/`1d`) / `project_ids` / `user_ids` / `api_key_ids` / `models` / `batch` / `group_by` / `limit` / `page`；响应桶含 `input_tokens`、`output_tokens`、`num_model_requests` 等。
  - `GET https://api.openai.com/v1/organization/costs`：`start_time`(必) / `end_time` / `bucket_width`(**只支持 `1d`**) / `project_ids` / `api_key_ids` / `line_items` / `group_by`(`project_id|user_id|line_item|api_key_id|api_source`) / `limit`(1–180，默认 7)；响应 `results[].amount = { value, currency }`。
- 认证：**Admin API Key**（`Bearer`）。普通 `sk-…` 用户 key 无权访问 organization 端点（403）；项目/服务账号 key 也不行。
- 公开性：**公开官方 API**。
- 证据：
  - OpenAPI 规范原文：<https://github.com/openai/openai-openapi/blob/master/openapi.yaml>（`/organization/costs` @行 12085、`/organization/usage/completions` @行 18074、`securitySchemes.AdminApiKeyAuth` @行 124012）
  - 社区实现对照：<https://github.com/steipete/CodexBar/blob/main/docs/openai.md>（`GET /v1/organization/costs`、`/v1/organization/usage/completions`、`bucket_width=1d`、`OPENAI_ADMIN_KEY` 与普通 key 的差别）

**建议**：Codex provider 主路径 = 方案 A（`primary/secondary` 双窗口，与 OpenCode Go 三窗口同构，UI 复用现成百分比限额行）；`supportsUsage = false` 首版。

### 2.3 Cursor

#### 方案 A（推荐，个人订阅额度）：dashboard 前端接口

- 端点（同一 Cookie 会话）：
  - `GET https://cursor.com/api/usage-summary` —— **主数据**：计划额度 + 计费周期。
  - `GET https://cursor.com/api/auth/me` —— 稳定用户 ID / 邮箱 / 名称。
  - `GET https://cursor.com/api/usage?user=<id>` —— 旧版请求数配额。
  - `GET https://cursor.com/api/dashboard/v2/usage-status?scope=user` —— 统一会员的月度追加花费。
  - `POST https://cursor.com/api/dashboard/get-sand-usage-status` —— Grok Bot 周额度（`usagePercent`、`nextResetTimestampUtc`），需 `Origin: https://cursor.com`。
  - `POST https://cursor.com/api/dashboard/get-filtered-usage-events` —— 逐请求 token/花费（成本统计用）。
- 认证（三选一，按可用性降级）：
  1. **Cookie** `WorkosCursorSessionToken={userId}%3A%3A{JWT}`；
  2. **Cursor.app 本地 token**：SQLite `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` 的 `ItemTable` 键 `cursorAuth/accessToken`（JWT；新版可能是 `cursor-safe-storage:v1:` 加密串，需 Keychain `Cursor Safe Storage`）；
  3. `cursor-agent login` 的 `cursor-agent/auth.json` `accessToken`。
  - 写请求必须带 `Origin: https://cursor.com` / `Referer: https://cursor.com/dashboard`（Cloudflare CSRF）。
- `/api/usage-summary` 返回字段（Swift DTO 原文）：
  - `billingCycleStart` / `billingCycleEnd`（ISO8601 字符串）、`membershipType`、`limitType`、`isUnlimited`；
  - `individualUsage.plan`：`used` / `limit`（**分**）与 `totalPercentUsed` / `autoPercentUsed` / `apiPercentUsed`（**已是百分比单位**，可能小于 1）；
  - `individualUsage.overall`（团队/企业成员的个人员度上限，分）、`individualUsage.onDemand`（`used/limit`，分）；
  - `teamUsage.pooled`（团队共享池，分）、`teamUsage.onDemand`。
- 映射建议：`plan.totalPercentUsed`（或 auto+api 之和）→ 一条月窗口 `BillingPercentLimit`；`billingCycleEnd` → `resetsAt`；`onDemand.used/limit` → 第二条（追加花费）或 `purchasedUSD`。
- 公开性：**非公开端点**（dashboard 前端自用），**可能失效**（社区 ADR 明确记录「undocumented upstream contract, 上游一改就静默过期」）。
- 证据：
  - 端点清单与 Cookie 名 / 取值格式 / CSRF 头：<https://github.com/steipete/CodexBar/blob/main/docs/cursor.md>（`:122-132` 端点、`:66` Cookie 名、`:186` `get-filtered-usage-events`）
  - 响应字段（Swift DTO 与解析）：<https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Cursor/CursorStatusProbe.swift>（`:201-229` `CursorUsageSummary`/`CursorIndividualUsage`、`:1224-1228` `/api/usage-summary` 调用）与 <https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Cursor/CursorStatusProbe%2BUsageSummary.swift>（`:15-95` 百分比与分值换算）
  - `state.vscdb` 取 token、Cookie 拼接格式、必带 Origin/Referer：<https://github.com/siropkin/budi/wiki/Cursor-Usage-API-Contract>（`:~55-85`）

#### 方案 B（官方 API，团队/组织用量）

- 端点：`POST https://api.cursor.com/organizations/spend`、`POST /organizations/daily-usage-data`、`POST /organizations/pooled-usage`、`POST /organizations/filtered-usage-events`（团队侧同构：`/teams/spend`、`/teams/daily-usage-data`）。
- 认证：**Basic auth**，API Key 作用户名、密码留空；scope `usage:*`（`admin:*` 亦可）。组织端点要 Organization API Key，`/teams/*` 要 Team API Key。
- 请求/响应要点（`daily-usage-data`）：`organizationId`(必)、`startDate`/`endDate`（epoch ms，**区间 ≤30 天**）、`teamIds`、`page/pageSize`(≤1000)；响应 `data[]` 每行含 `userId/teamId/day/email/subscriptionIncludedReqs/apiKeyReqs/usageBasedReqs/composerRequests/agentRequests/mostUsedModel…`，另有 `pagination` 与 `period`。
- 公开性：**公开官方 API**（Cursor 文档站点的 Organization/Team Admin API 章节）。
- 证据：
  - 官方文档：<https://cursor.com/docs/account/organizations/organization-admin-api.md>（Basic auth `:5`、scope 表 `:29-35`、`/organizations/daily-usage-data` 与字段 `:~"### Get Daily Usage Data"` 段）与 <https://cursor.com/docs/account/teams/admin-api.md>
  - 文档索引（证明章节存在）：<https://cursor.com/docs/llms.txt>（`admin-api.md`、`organization-admin-api.md#get-spending-data`、`#get-daily-usage-data`、`#get-pooled-usage`）

**建议**：Cursor provider 主路径 = 方案 A（Cookie/JWT，个人订阅月度窗口 + `billingCycleEnd` 重置）；方案 B 留作「组织 Key 实例」的第二形态。

### 2.4 横向对比与落地风险

| 维度 | Claude | Codex | Cursor |
|---|---|---|---|
| 主路径认证形态 | OAuth access token（`Bearer`） | OAuth access token（`Bearer`） | Cookie（`WorkosCursorSessionToken`）或本地 JWT |
| 凭据可粘贴性 | 可直接粘贴 token | 可直接粘贴 token | Cookie 串较长（含 `%3A%3A`），需提示格式 |
| 窗口数 | 2–6（5h / 周 / 模型周 / 附加） | 2 + N（5h / 周 / 附加） | 1–2（月 / 统一周池 / 追加花费） |
| 重置时间字段 | `resets_at`（ISO8601） | `reset_at`（epoch 秒） | `billingCycleEnd`（ISO8601）、`nextResetTimestampUtc` |
| 官方 API 覆盖订阅窗口 | 否 | 否 | 否 |
| 失效风险 | 中（社区长期使用） | 中高（内部后端） | 中高（dashboard 接口，历史上变过） |

**共同结论**：三家主路径都是**非公开端点**。因此新 provider 必须遵守现有 `BillingError` 语义——解析失败 → `.invalidResponse`（`BillingProvider.swift:80-81`），HTTP 401/403/429 分别映射（`BillingProvider.swift:47-86`），并且 `minimumRefreshInterval` 取保守值（建议 300 秒，参照 `OpencodeGoBillingProvider.swift:24-25`「官方未公布限流 → 5 分钟」），避免撞未知限流后整块失败。

**凭据是单个 String 的应对**：三种认证形态（API Key / Cookie / OAuth token）建议在 provider 内部按前缀分派（如 `cookie:` / `token:` / 裸串即 API Key），而不是扩协议——这样 `BillingCredentialStore` 与 `ProviderDescriptor` 都不用动，UI 侧只需把 `credentialHint` 按 provider 写清（`BillingProvider.swift:33`）。

---

## 3 同一 provider 多实例：数据模型改造

### 3.1 目标模型

- **类型（kind）**：`cursor` / `codex` / `claude` / 现有 `ollama` / `open-design` / `opencode-go`。
- **实例（instance）**：`instanceID`。规则建议：
  - **默认实例 `instanceID == kindID`**（如 `cursor`）→ 现有凭据/启用偏好键**零迁移**；
  - **命名实例 `instanceID == "<kindID>::<slug>"`**（如 `cursor::work`），`slug` 由用户命名（小写字母/数字/连字符）。
  - 选择 `::` 的理由：`billing.credential.` / `billing.enabled.` 已有前缀（`BillingCredentialStore.swift:96`、`BillingProviderPreferences.swift:15`），`::` 不与其冲突，且一个 `kindID` 的可解析前缀天然唯一。
- **凭据键**：`billing.credential.<instanceID>`（沿用 `BillingCredentialStore.swift:116-118`，无需改函数签名）。
- **启用键**：`billing.enabled.<instanceID>`（沿用 `BillingProviderPreferences.swift:24-26`）。
- **环境变量键**：默认实例 = 现有规则；命名实例 = `BILLING_<KIND>_<SLUG>_API_KEY`（需要把 `:` 替换为 `_`）。

### 3.2 关键设计：装饰器而非改协议

不改 `BillingProvider` 协议、不改 `BillingMonitor`，用**装饰器**把「类型 + 实例」合成一个 `id` 已经是 `instanceID` 的 provider：

```swift
// 新增 Sources/NetworkMonitorCore/Billing/BillingProviderInstance.swift
public struct BillingProviderInstance: BillingProvider {
    public let base: any BillingProvider      // 原实现（id = kindID）
    public let instance: BillingInstance       // instanceID + title
    public var id: String { instance.id }
    public var displayName: String { instance.title }
    public var credentialHint: String { base.credentialHint }
    public var environmentCredentialKey: String { instance.environmentKey }
    // 其余能力位与 fetch 全部转发 base
}
```

收益（逐条可验证）：
- `BillingMonitor` 的 `states/generations/lastAttempts` 键是 `descriptor.id`（`BillingMonitor.swift:33-37`）→ **自动变多实例**；
- `collectFetchTargets` 用 `registry.provider(id: id)`（`BillingMonitor+Fetching.swift:37`）→ 注册表按 instanceID 查即可；
- 限额提醒键 `<providerID>.<resourceID>`（`BillingAlerts.swift:99`）→ 自动按实例隔离；
- `BillingVisibilityRule`（`BillingVisibility.swift:23-38`）与 `Snapshot.state(for:)`（`BillingMonitorSnapshot.swift:93-95`）不感知实例，零改动；
- 现有三个 provider 实现（`OllamaBillingProvider` / `OpenDesignBillingProvider` / `OpencodeGoBillingProvider`）**一行不改**。

代价：`ProviderDescriptor` 建议补两个字段（供 UI 区分同类型实例）——`kindID` 与可选的 `instanceLabel`。

### 3.3 文件级改动清单（精确到现有签名与行号）

#### Core（`Sources/NetworkMonitorCore/Billing/`）

| 文件 | 改动 | 现有签名/行号 |
|---|---|---|
| **新增** `BillingInstance.swift` | `public struct BillingInstance: Sendable, Equatable`（`id/kindID/title`）；`public enum BillingInstanceID`：`make(kindID:slug:)` / `kind(of:)` / `slug(of:)` / `isDefault(_:)` / `environmentKey(kindID:slug:)` | — |
| **新增** `BillingProviderInstance.swift` | 装饰器（见 §3.2） | — |
| **新增** `BillingInstanceStore.swift` | 实例列表持久化：`instances() -> [BillingInstance]`、`add(kindID:slug:title:) throws -> BillingInstance`（重名/非法 slug 抛领域错误）、`rename(instanceID:title:)`、`remove(instanceID:)`（连带删凭据与启用键需在调用方显式做）；存储键建议 `billing.instances`（JSON） | — |
| `BillingProvider.swift` | `register` 语义从「按 id 覆盖」明确为「按 instanceID 覆盖」；建议新增 `providers(ofKind:)` 与 `instances` | `register(_ provider: any BillingProvider)` `:106-111`；`all` `:114-118`；`provider(id:)` `:121-123` |
| `BillingCredentialStore.swift` | 函数体不改（键已是 `前缀 + id`）；**注释契约要改**（`:5-13`「同一 provider 只有一份」→「同一实例只有一份」）；`defaultEnvironmentKey` 增加命名实例分支 | `storageKey(for:)` `:116-118`；`defaultEnvironmentKey(for:)` `:121-123`；`credentialResolution(for:)` `:148-165` |
| `BillingProviderPreferences.swift` | 语义改「按实例」；`storageKey/resetEnabled` 不变 | `storageKey(for:)` `:24-26`；`isEnabled(_:)` `:29-33`；`setEnabled(_:for:)` `:36-38` |
| `BillingVisibility.swift` | 不改 | `:23-44` |
| `BillingRefreshScheduler.swift` | 不改 | `:21-37` |

#### 可执行目标（`Sources/NetworkMonitor/Billing/`、`Settings/`、`MenuPanel/`）

| 文件 | 改动 | 现有签名/行号 |
|---|---|---|
| `AppCoordinator.swift` | 组合根：从「三个 provider 字面量」改为「按 `BillingInstanceStore` 展开实例 + 装饰器包装」；`migrateLegacyPlaintext` 传实例列表 | `:110-114`（注册表字面量）、`:116-120`（环境键解析闭包）、`:122`（迁移）、`:126-129`（Monitor 构造） |
| `BillingMonitor.swift` | API 语义改名（参数 `providerID:` → `instanceID:`，内部键不变），新增 `addInstance/removeInstance` 入口（重建 states） | `saveCredential(_:providerID:)` `:179-194`；`clearCredential(providerID:)` `:197-210`；`selectRange(_:providerID:)` `:108-150` |
| `BillingMonitor+Providers.swift` | `setProviderEnabled(_:providerID:)` → 按实例；`makeState` 填 `descriptor.kindID`；`rebuildStates` 用实例顺序 | `:16-29`、`:32-51`、`:54-67` |
| `BillingMonitorSnapshot.swift` | `ProviderDescriptor` 补 `kindID` 与 `instanceLabel`（`:13-48` 初始化器同步） | `:13-48` |
| `SettingsProvidersPane.swift` | 行按实例展开；同 kind 下提供「＋ 新增实例 / 重命名 / 删除」；`rows` 键改 instanceID；页脚文案改写 | `rows: [String: ProviderRowView]` `:33`、`buildContent` `:53-72`、`refresh` `:94-111`、`save` `:136-154`、`setRowsLocked` `:166-170`、文案 `:83-84` |
| `SettingsProviderRowView.swift` / `+Editing.swift` | 增加「实例名」展示与重命名入口（行内编辑已有范式） | 类 `:10-248`；编辑 `:8-237` |
| `MenuPanel/BillingProviderBlockView.swift`、`BillingPaneSections.swift`、`BillingPaneView.swift`、`BillingHeroView.swift` | 卡片标题显示实例后缀（`displayName` 已带即可，可选）；`BillingPaneView.syncBlocks` 以 `descriptor.id` 为键（`:154-170`）——若按实例渲染，块数随之增加，需要验证布局高度预算 | `BillingPaneView.syncBlocks` `:154-170`、`update` `:116-151` |
| `MenuPanel/BillingPanePreview.swift`、`Debug/BillingVisibilitySnapshot.swift` | 预览/快照 fixture 补 `kindID`/实例态 | `makeState` `:47-79` |
| `BillingAlertService.swift` | 入参改名（`providerID` → `instanceID`），通知标题用实例名 | `protocol BillingAlerting.handle(...)` `:9-12`、`handle(...)` `:51-65` |

#### 测试（`Sources/TestRunner/`）

| 文件 | 改动 |
|---|---|
| `BillingVisibilityTests.swift` | **必须重写** `:51-102`：把「同 id 唯一」改为「同 instanceID 唯一、同 kindID 可多实例」；把 `secrets.values.count == 1` 改为「两个实例各一条，互不覆盖」；新增「命名实例环境变量键」断言（`:99-101` 预期数组要改） |
| `BillingDecodingTests.swift` | `:178-194` `testProviderRegistry` 需覆盖多实例注册 |
| `BillingTests.swift` | `testBillingProviderPreferences`（`:159-195`）增加实例维度 |
| `BillingAlertTests.swift` | 见 §4：新增恢复通知用例 |
| 新增 `BillingInstanceTests.swift` | `BillingInstanceID` 解析/构造/非法 slug；`BillingInstanceStore` 增删改查；装饰器转发与能力位 |

### 3.4 迁移与兼容

- **默认实例 id == kindID** → `billing.credential.<id>`、`billing.enabled.<id>`、提醒状态键 `<id>.<resource>` 全部原样命中，老用户升级零感知（不需要新的迁移函数）。
- 首次写入实例列表时，对注册表里每个 kind 生成默认实例（`slug = nil`），避免「列表为空 → 额度页空态」。
- 删除实例时按「先清凭据 → 再清启用键 → 最后改列表」的顺序，并对在途请求递增代次（沿用 `BillingMonitor.swift:318-322` 的 `nextGeneration` 语义），防止已删实例的回包写回状态。
- `AGENTS.md` 与 `SettingsProvidersPane` 页脚文案、`BillingCredentialStore` 头注释三处「同一 provider 只有一份凭据」的表述**必须同步改写为实例语义**（`docs/索引.md` 与 `AGENTS.md` 的功能表同源）。

### 3.5 单测口径改写示例（关键三行）

现有（`BillingVisibilityTests.swift:57-58`）：
```swift
assertEqual(registry.all.count, 2, "同 id 重复注册不新增条目")
assertEqual(registry.all.filter { $0.id == "ollama" }.count, 1, "同 id 在注册表里唯一")
```
改为：
```swift
registry.register(StubProvider(id: "ollama"), instance: .default(kindID: "ollama"))
registry.register(StubProvider(id: "ollama"), instance: .named(kindID: "ollama", slug: "work", title: "Ollama（工作）"))
assertEqual(registry.all.filter { BillingInstanceID.kind(of: $0.id) == "ollama" }.count, 2, "同类型可多实例")
assertEqual(registry.all.filter { $0.id == "ollama" }.count, 1, "默认实例 id 仍等于 kindID")
```

---

## 4 额度恢复通知：需要的信号与 Core 改造

### 4.1 现有 `BillingAlertEvaluator` 逻辑（`Sources/NetworkMonitorCore/Billing/BillingAlerts.swift`）

- 阈值表 `BillingAlertThresholds.percentages = [5, 4, 3, 2, 1]`（`:8`）；`reachedThreshold(remainingFraction:)`（`:14-18`）取「不小于当前剩余的最小阈值」，一次跨多档只命中最低档。
- 状态 `BillingAlertState`（`:22-32`）：`cycleID: String?` + `notifiedThreshold: Int`。**只有这两个字段。**
- 提醒 `BillingAlert`（`:35-76`）：`key / providerID / resourceTitle / threshold / remainingPercent / resetAt`；`isCritical`（`:59`）、`title(providerName:)`（`:62-64`）、`bodyText`（`:69-75`，末尾拼 `resetAt` 的重置文案）。
- 评估 `evaluate(balance:providerID:state:)`（`:89-142`）：
  - 只遍历两类资源：`balance.included`（`:127-133`，`cycleID = period.end 的 ISO 串`）与 `balance.percentLimits`（`:134-140`，`cycleID = resetsAt 的 ISO 串`）。
  - 内部 `consider`（`:97-125`）：
    1. **周期变化即重置记录**：`previous.cycleID == cycleID` 才继承 `notifiedThreshold`，否则归 0（`:102-105`）；
    2. 剩余 >5% → 若曾提醒过则把 `notifiedThreshold` 清 0（`:107-114`）——**静默清状态，不发通知**；
    3. `notifiedThreshold == 0 || threshold < notifiedThreshold` 才发（`:115-123`）。→ 同周期同档只发一次，跌破更低档再发一次。
- 落地：`BillingAlertService.handle(...)`（`BillingAlertService.swift:51-65`）把结果状态整体 JSON 落 `billing.alert.state`（`:24`），并逐条 `post`；开关在 `BillingAlertPreferences.enabledKey = "billing.alerts.enabled"`（`BillingAlertPreferences.swift:12`，缺省开）。

### 4.2 缺口（对应任务里的三个信号）

| 需要的信号 | 现状 | 缺口 |
|---|---|---|
| **周期重置时间** | 有 `resetAt`/`resetsAt`（`BillingAlerts.swift:49,131-139`），但只当作 `cycleID` 的字符串来源 | 没有「重置发生」这个事件：周期一换只是**重置已提醒记录**，用户收不到「额度已刷新」通知 |
| **余额回升百分比** | `remainingFraction` 有；回升只做 `:109-113` 的静默清零 | 没有「回升多少」的记录与阈值，也没有「回升了 N 个百分点」的通知文案 |
| **周额度窗口** | `BillingPercentLimit` 只有 `id/title/resetsAt`（`BillingModels.swift:82-115`） | 没有窗口种类（session 5h / weekly / monthly）与窗口时长，无法区分「5 小时窗口重置」与「周窗口重置」，也无法判断「周额度按 7 天滚动」 |

### 4.3 建议新增的字段与纯函数（全部放 Core，便于 TestRunner 断言）

1. `BillingModels.swift` —— 新增窗口模型，挂到 `BillingPercentLimit`：
   ```swift
   public enum BillingWindowKind: String, Sendable { case session, daily, weekly, monthly, custom }
   public struct BillingQuotaWindow: Sendable, Equatable {
       public let kind: BillingWindowKind
       public let duration: TimeInterval     // 5h=18000 / 周=604800 / 月=2592000 或按账单周期
       public let resetsAt: Date
       public let cycleID: String            // 稳定周期标识（ISO8601 重置时刻）
   }
   // BillingPercentLimit 增加：public let window: BillingQuotaWindow?（resetsAt 保留为兼容字段）
   ```
2. `BillingAlerts.swift` —— 状态扩字段（Codable，旧 JSON 解码容错）：
   ```swift
   public struct BillingAlertState: Codable, Sendable, Equatable {
       public var cycleID: String?
       public var notifiedThreshold: Int
       public var lastRemainingFraction: Double?     // 上次观测剩余（回升判定基线）
       public var lastWindow: BillingQuotaWindow?    // 上次观测窗口（重置判定基线）
       public var lastObservedAt: Date?
       public var lastResetNotifiedCycleID: String?  // 同一周期只发一次重置通知
       public var lastRecoveryNotifiedAt: Date?      // 回升通知冷却
   }
   ```
3. `BillingAlerts.swift` —— 提醒增加种类与文案：
   ```swift
   public enum BillingAlertKind: Sendable, Equatable {
       case threshold(Int)          // 现有 5…1%
       case windowReset             // 周期重置（额度已刷新）
       case balanceRecovered        // 余额回升（百分比）
   }
   // BillingAlert 新增：kind、recoveredPercent: Double?、windowTitle: String?
   ```
4. **新增** `BillingRecoveryRule.swift`（纯函数）：
   ```swift
   public enum BillingRecoveryRule {
       /// 窗口是否发生重置：resetsAt 前进 或 cycleID 变化
       public static func isWindowReset(previous: BillingQuotaWindow?, current: BillingQuotaWindow) -> Bool
       /// 回升百分点（负值归 0）
       public static func recoveredPercent(from previous: Double?, to current: Double) -> Double
       /// 是否达到通知条件（默认阈值 10 个百分点）
       public static func shouldNotifyRecovery(recoveredPercent: Double, minimumPercent: Double) -> Bool
       /// 去重：同一 cycleID 的重置只通知一次
       public static func shouldNotifyReset(previousState: BillingAlertState, current: BillingQuotaWindow) -> Bool
   }
   ```
5. `BillingAlertPreferences.swift` —— 新增开关（缺省开 / 缺省 10）：
   - `billing.alerts.reset.enabled`
   - `billing.alerts.recovery.enabled`
   - `billing.alerts.recovery.minPercent`（默认 10）
6. `BillingAlertEvaluator.evaluate` 的 `consider(...)` 增加入参 `window: BillingQuotaWindow?`，在阈值判定前后各加一步：先判重置（`windowReset`），再判回升（`balanceRecovered`），最后判阈值——**重置与回升都会把 `notifiedThreshold` 归 0**，保证下一轮下跌能重新提醒。

### 4.4 三家 provider 能提供的恢复信号（决定通知可用性）

| provider | 周期重置时间 | 余额回升百分比 | 周窗口 |
|---|---|---|---|
| Claude（OAuth usage） | ✅ 每个窗口 `resets_at` | ✅ `utilization` 逐次可算差值 | ✅ `seven_day*`（含模型专属） |
| Codex（wham/usage） | ✅ `reset_at`（epoch 秒） | ✅ `used_percent` 差值 | ✅ `secondary_window`（`limit_window_seconds≈604800`） |
| Cursor（usage-summary） | ✅ `billingCycleEnd`（月）；统一会员的周池另有 `nextResetTimestampUtc` | ✅ `totalPercentUsed` 差值 | ⚠️ 仅统一会员（The X Subscription 共享周池），普通计划按月 |
| Claude/OpenAI/Cursor（官方 Admin API） | ❌ 只有日桶 / 花费，无订阅窗口 | ❌（花费回升不是额度回升） | ❌ |

结论：**恢复通知的完整度取决于主路径（订阅端点）而非官方 API**；Cursor 的周窗口只在统一会员场景存在，其余按「月窗口重置」通知，文案里用窗口名区分即可。

### 4.5 前端展示口径建议（与现有 UI 一致）

- 重置通知文案：`<实例名> · <窗口名>额度已重置`，正文「已恢复至 100%，下次重置 11/20 08:00」。
- 回升通知文案：`<实例名> · <窗口名>额度回升`，正文「剩余 3.2% → 18.6%（+15.4 个百分点）」。
- 两者都复用现有 `BillingAlert.bodyText` 的时间格式（`formatShortDateTime`，见 `:69-75`），不新增格式器。

---

## 5 落地顺序（建议）

1. **多实例底座**（Core 新增 `BillingInstance` / `BillingProviderInstance` / `BillingInstanceStore` + 注册表语义 + 单测改写）——不动现有三个 provider，先让 `ollama` 能起两个实例验证全链路。
2. **恢复通知信号**（模型窗口 + 状态扩展 + 纯函数 + 评估器接入 + 单测）——同样可先用 `opencode-go` 的三窗口（5h/周/月）验证，因为它的 `OpencodeGoWindow` 已经是「多窗口 + resetsAt」形态（`OpencodeGoBillingProvider.swift:87-116`）。
3. **三个新 provider**（每个 = 1 个主类 + 1 个 DTO 文件 + 1 个解码纯函数 + 测试），按 Claude → Codex → Cursor 顺序（前两者窗口模型一致，可复用同一套映射）。
4. **设置页与文案同步**（新增实例入口、页脚文案、AGENTS.md 功能表口径）。

风险与对策：
- 非公开端点失效 → 解析失败走 `.invalidResponse`，面板保留上次成功数据（`BillingMonitor.swift:246-299` 已是此语义），并保持 `minimumRefreshInterval=300` 少打接口。
- Cookie 类凭据（Cursor）在 `EncryptedSecretStore` 里是长字符串（`BillingCredentialStore.swift:182-186` 只做 trim），长度不是问题；UI 掩码 `SettingsProvidersPane.mask`（`:183-187`）保留前 3 后 4 已够用。
- 单文件 500 行 / 15 KiB 门禁：新 provider 按 `OpencodeGoBillingProvider`（209 行）+ `OpencodeGoBillingDTOs`（72 行）的拆法即可，不要写成单文件。

---

## 6 待办（本身不在本调研范围）

- `docs/索引.md` 的「调研」章节需要新增一条指向本文（本文未改索引文件，交给实现任务一并提交，避免与视觉/实现任务冲突写同一文件）。
- `AGENTS.md` 功能模块表的额度 Provider 描述需按实例语义改写。
