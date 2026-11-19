# 网络 / 外部世界访问层审计（只读）

- 审计范围：`NetworkMonitor/Sources` 全部 target（不含 TestRunner 的统计口径；TestRunner 只在需要对照时点名）
- 手段：只读 grep / read，**未构建、未运行**（构建归 leader）
- 结论一句话：**这一层没有成层**。HTTP 出网有 6 个实现、17 个出网点，其中只有 6 个走同一个封装，而那个封装还焊在 App target 里，Core 侧的 3 家 provider 用不到它；Process / UDP / HTTP 服务端 / 文件系统各有入口但互不相通；成功率 / 耗时 / 失败原因的观测出口不存在（只有文本日志）。

---

## 1. URLSession 清单（全仓，不含 TestRunner）

统计口径：一次 `session.data(for:)` / `dataTask` = 一个出网点；同一实现里的多条路由按出网点计数。

```
grep -rn 'session\.data(for' NetworkMonitor/Sources --include=*.swift   → 5 处（不含 TestRunner）
grep -rn 'URLSession' ...                                              → 28 处（不含 TestRunner 时：23）
```

### 1.1 有封装：6 个出网点 / 1 个实现

唯一封装是 `BillingHTTPClient`（**在 App target，不在 Core**）：

| 出网点 | 域名 + 路径 | 超时 | UA | 自建 config | 重试 | Retry-After | 错误映射 |
|---|---|---|---|---|---|---|---|
| Claude | api.anthropic.com `/api/oauth/usage` | 15 | `NetworkMonitor/1.0 (macOS)` | 否（`.shared`） | 无 | 解析（HTTP:62） | ClaudeBillingModels.swift:113 |
| Codex | chatgpt.com `/backend-api/wham/usage` | 15 | 同上 | 否 | 无 | 解析 | CodexBillingModels.swift:148 |
| Cursor | cursor.com `/api/usage-summary` | 15 | 同上 | 否 | 无 | 解析 | CursorBillingModels.swift:171 |
| DeepSeek | api.deepseek.com `/user/balance` | 15 | 同上 | 否 | 无 | 解析 | DeepSeekBillingModels.swift:79 |
| OpenRouter | openrouter.ai `/api/v1/key` | 15 | 同上 | 否 | 无 | 解析 | OpenRouterBillingModels.swift:78 |
| Moonshot | api.moonshot.cn `/v1/users/me/balance` | 15 | 同上 | 否 | 无 | 解析 | MoonshotBillingModels.swift:70 |

- 封装本身：`NetworkMonitor/Billing/Providers/BillingProviderHTTP.swift:11-82`（超时 :14、UA :16/:45-47、Accept :48-50、Retry-After :62、错误体提取 :70-81）
- **关键结构缺陷**：该文件 `import NetworkMonitorCore`（:2）——它在 App target。Core 侧的 3 家 provider（`NetworkMonitorCore/Billing/OllamaBillingProvider.swift` 等）**物理上无法 import 它**，所以只能各自重写一份 transport（见 1.2）。

### 1.2 裸调：11 个出网点 / 5 个实现

| 出网点 | 域名 + 路径 | 超时 | UA | 自建 config | 重试 | Retry-After | 错误映射 |
|---|---|---|---|---|---|---|---|
| Ollama 余额 | ollama.com `/api/balance`（OllamaBillingProvider.swift:42） | 20（:81） | **无** | 否 | 无 | 解析（:112） | 内联 switch :104-118 |
| Ollama 用量 | ollama.com `/api/usage`（:52） | 20 | **无** | 否 | 无 | 解析 | 同上 |
| OpenDesign 计划用量 | amr-api.open-design.ai `/api/v1/workspaces/{id}/billing/coding-plan-usage`（OpenDesignBillingProvider.swift:70） | 20（:145） | **无** | 否 | 无 | 解析（:182） | 内联 switch :169-188 |
| OpenDesign 工作区 | 同域 `/api/v1/workspaces`（:119） | 20 | **无** | 否 | 无 | 解析 | 同上 |
| OpencodeGo 用量 | opencode.ai `usagePath`（OpencodeGoBillingProvider.swift:146） | 20（:152） | **无** | 否 | 无 | 解析（:175） | `mapHTTPError` :180-198 |
| 更新检查 | api.github.com `/repos/baosfeng/toolbar/releases/latest`（UpdateChecker.swift:146） | 8（:90/:151） | `一览/<版本>`（AppCoordinator+Update.swift:53） | 否（`.reloadIgnoringLocalCacheData` 改的是请求 :154） | 无 | **不解析**（403/429 → rateLimited 无秒数，:176-186） | UpdateCheckError :44-71 |
| 局域网 `GET /info` | `{ip}:{port}`（TransferHTTPClient.swift:47-51） | 60 / 资源 3600（:20-22） | **无** | **是**（ephemeral，:26-31） | 有（Service 层 1s/2s/4s） | **不解析** | TransferError.ioFailed（:173-188） |
| 局域网 `POST /offer` | 同上（:55-62） | 同上 | 无 | 是 | 有 | 不解析 | 业务码 envelope（:211-223） |
| 局域网 `GET /offer/status` | :71 | 同上 | 无 | 是 | 有 | 不解析 | 同上 |
| 局域网 `PUT /upload` | :83-96（`uploadTask` 文件流 + 进度 delegate :230） | 同上 | 无 | 是 | 有（断点续传 :220） | 不解析 | 同上 |
| 局域网 `POST /cancel` | :107-110 | 同上 | 无 | 是 | 有 | 不解析 | 同上 |

合计：**17 个出网点 / 6 个实现**（BillingHTTPClient、Ollama、OpenDesign、OpencodeGo、GitHubUpdateChecker、TransferHTTPClient）。派发口径里的「15 处」按 URLSession 实例数或按 JSON 出网点数算；实际按请求发起点数是 17。

---

## 2. 重复实现度：同一件事有 N 份

| 事项 | 实现份数 | 位置 |
|---|---|---|
| 超时值 | **5** | BillingHTTPClient 15（:14）· Ollama/OpenDesign/OpencodeGo 各 20（三处硬编码）· UpdateChecker 8（:90）· Transfer 60/3600（:20-22） |
| User-Agent | **2**（8 个出网点无 UA） | BillingProviderHTTP.swift:16 · AppCoordinator+Update.swift:53 |
| 状态码 → 错误 | **8 处实现 / 5 套语义**（6 处映射同一 BillingError） | BillingHTTPErrorMapper :73-88 · Claude/Codex/Cursor/DeepSeek/OpenRouter/Moonshot 各自 `mapHTTPError`（Models 文件）· OpencodeGo 自带 :180-198 · Ollama 内联 :104-118 · OpenDesign 内联 :169-188 · UpdateChecker :176-186 · Transfer envelope :211-223 |
| 错误体文案提取 | **5** | BillingProviderHTTP :70-81 · Ollama :122-125 · OpenDesign :192-197 · OpencodeGo :176+ · UpdateChecker :188-194（截 60 字） |
| 传输失败日志 | **5 句**（字段各不相同，均无 provider/URL/耗时/status 结构） | OllamaBillingProvider.swift:94 · OpenDesignBillingProvider.swift:159 · OpencodeGoBillingProvider.swift:165 · BillingProviderHTTP.swift:56 · UpdateChecker.swift:125/128/136 |
| Retry-After 解析 | **4** | BillingProviderHTTP :62 · Ollama :112 · OpenDesign :182 · OpencodeGo :175（Update / Transfer 完全不解析） |
| 重试 | **1**（其余 16 个出网点零重试） | TransferService+Send.swift:209（1s/2s/4s），其余无 |
| 请求构造（URLComponents + path + query） | **4** | Ollama :65-85 · OpenDesign :131-150 · OpencodeGo :140-156 · TransferHTTPClient :119 |

一句话：**同一件「发一个 GET 拿 JSON」的事，写了两遍传输层（App 一份、Core 三份）、一遍走捷径（Update）、一遍带自己的 config（Transfer）。**

---

## 3. 外部进程与文件：HTTP 之外的「外部世界」

| 类别 | 入口 | 有封装？ | 证据 |
|---|---|---|---|
| HTTP 服务端（局域网收文件 / 扫码） | `HttpServer` + `NWListener` | ✅ 有（但只服务传输功能） | HttpServer.swift:24/:71/:113 |
| UDP 局域网发现 | `UdpDiscoveryService` 直接 BSD socket | ✅ 有（功能内自洽） | UdpDiscoveryService+Socket.swift:21/:69/:101，组播 239.255.77.77:53318 |
| 子进程：nettop | `runNettopSnapshot()` 全局函数 | ❌ 无（直接 `Process()`） | Core.swift:168-188 |
| 子进程：zstd 定位（登录 shell） | `HarnessZstdLocator.locateViaLoginShell` | ⚠️ 半（收敛在 Locator 内） | HarnessZstdLocator.swift:107-126 |
| 子进程：zstd 流式解码 | `HarnessZstdLineStreamer.streamWithProcess` | ⚠️ 半（与内置 dlopen 并存，两条路径） | HarnessZstdLineStreamer.swift:99/:127-133 |
| 子进程：其他（调试探针） | ClipboardPreviewProbe.swift:119 · ClipboardPerfProbe.swift:288 · LaunchServicesRegistrar.swift:44 · nmcli/Capture.swift:75 | ❌ 各自一份 | 四处独立 `Process()` |
| dlopen 私有/系统库 | 3 处 | ❌ 无 | SystemThermalReader.swift:156 · SystemGPUPowerReader.swift:166 · HarnessZstdDecoder.swift:113 |
| 文件系统 | `FileManager.default` **83 处**（不含 TestRunner） | ❌ 无统一入口，也没有路径常量层；`~/Library/Application Support/macMonitor` 至少 5 处在各自拼 | DatabaseManager.swift:67 · EncryptedSecretStore.swift:135 · CueSoundFileStore.swift:30 · NotificationSoundFileStore.swift:55 · ClipboardImageStore.swift:38 |
| 目录扫描 | 4 处 `contentsOfDirectory` | ❌ | NotificationSoundLibrary.swift:82 · NotificationSoundInstaller.swift:105 · FileNameResolver.swift:52 · NotificationDebugSelfCheck.swift:104 |
| Unix domain socket 监听 | **不存在** | — | `grep -rn 'AF_UNIX\|UnixDomainSocket\|NWEndpoint.unix'` → 0 命中 |
| 外部 URL 打开 | `NSWorkspace.shared.open` 5 处 | ❌ | SettingsAboutPane.swift:172/177 · SettingsTransferPane.swift:244 · SettingsClipboardPane+Storage.swift:109 · SystemPermissionCenter.swift:198 |

结论：HTTP 收口只做了「传输功能内自洽」，**nettop / zstd / 系统库 / 文件系统这四类外部访问完全没成层**，其中文件系统最散（79 处、路径常量没有唯一真源）。

---

## 4. 可观测性

- **没有 metrics 出口**：`grep -rn 'os_signpost\|OSSignposter\|MetricKit\|Histogram'`（不含 TestRunner）→ **0 命中**。成功率 / 耗时 / 失败原因只能从 `OSLogLogger` 的文本里人肉 grep。
- 日志本身还有两个问题：`Loggers.swift:43-45` 全量 `%{public}@`（本机任意进程可读），却**没有结构化字段**——出网点失败日志里没有 provider id、URL、status、耗时中的任何一个（对照 §2「传输失败日志」5 句）。
- 唯一带策略的是计费刷新：60s 节流 + 429 全局退避（BillingMonitor.swift:13/:43，BillingMonitor+Apply.swift:47-61/:72-76），但这属于业务层，不是网络层能力——换一个出网点就没了。
- **用户可见性分层**：
  - 额度 → 可见：`BillingPaneStates.errorMessage`（:108）→ `BillingProviderBlockView.swift:185` 错误横幅。
  - 更新 → 可见：关于页「无法检查（原因）」（UpdateCheckError.userMessage :57-70）。
  - 传输 → 可见：会话状态机 + 会话失败日志（TransferService+Send.swift:278、TransferService+Receive.swift:207）。
  - **UDP 发现失败 → 不可见**：只有 `logger.warning`（UdpDiscoveryService+Socket.swift:56/:86/:117/:135），设置页通讯录空着没有任何原因。

---

## 5. 安全边界

- **凭据携带方式（全部在 header，无 cookie jar / 无环境变量）：**
  - `Authorization: Bearer` 7 处：OllamaBillingProvider.swift:82 · OpencodeGoBillingProvider.swift:153 · MoonshotBillingProvider.swift:81 · CodexBillingProvider.swift:53 · OpenRouterBillingProvider.swift:63 · ClaudeBillingProvider.swift:56 · DeepSeekBillingProvider.swift:66
  - `Cookie` 2 处：OpenDesignBillingProvider.swift:147（自己拼 `sessionCookieName=token`）· CursorBillingProvider.swift:55（整串 cookie 直塞）
  - 更新检查：匿名，无任何身份头（UpdateChecker.swift:155-157）
  - Transfer：`X-Pair-Key` 自定义头（TransferHTTPClient.swift:60）
- **凭据存储**：AES-GCM 密文落盘（EncryptedSecretStore.swift:40-42），键文件 `~/Library/Application Support/macMonitor/credentials.key`（:15）。
- **日志脱敏**：`LogRedaction` 全仓 41 处引用 / 不含 TestRunner 27 处，**在 Core/Billing 下 0 处**（`grep LogRedaction NetworkMonitorCore/Billing` → 0）。也就是说：
  - 9 个带凭据的出网点，**没有一个**有「日志脱敏」这一道；现有实现靠「不打印 URL、不打印 header」的自律（我复核了 Core/Billing + App/Billing + Update 的全部 30 条日志，确实没有打出 token/cookie 值——这是**没有泄露而非有防护**）。
  - 传输侧唯一把网络地址写进日志的是 TransferService+Scan.swift:27（`http://{局域网 IP}:{port}{pagePath}`，未脱敏）。
  - UDP 侧把 host 直接写日志：UdpDiscoveryService+Socket.swift:117/:135。
- 建议口径：脱敏应该下沉到 HTTP 层（URL 只留 host+path、header 白名单），而不是靠每个 provider 自觉。

---

## 6. 结论：能不能组装式复用

### 6.1 目标形态能覆盖多少

目标形态 = **唯一 `HTTPClient` + 声明式 `Endpoint`（baseURL / path / method / headers / timeout / 解码类型 / 错误映射）**。

- **可收口：15 个出网点**（12 个纯 JSON 请求-响应 + 3 个局域网 JSON 路由 info/offer/offerStatus/cancel 中的 JSON 部分）。它们的共同形状完全一致：拼 URL → 带 header → 拿 data+status → 映射错误 → 解码，差异只有 5 个字段（域名 / 路径 / 超时 / UA / 凭据头）。
- **不能收口：2 个**
  1. `PUT /upload`（TransferHTTPClient.swift:83-96 + 进度 delegate :230）：文件流上传 + `uploadTask(fromFile:)` + 逐块进度回调 + 断点 offset 协商（TransferService+Send.swift:220），需要 session 级 delegate，声明式 Endpoint 表达不了。
  2. `GET /offer/status` 的续传轮询语义：单次请求可收口，但它的「失败 → 1s/2s/4s 退避 → 读服务端已收字节再续」重试状态机在 Service 层，HTTP 层收不收口都要保留（TransferService+Send.swift:209/:220）。
- **天然不在这一层**（不该被 HTTPClient 吞掉，但应有各自唯一入口）：HttpServer（NWListener）、UdpDiscoveryService（BSD socket）、nettop 子进程、zstd 子进程 + dlopen、FileManager。

### 6.2 迁移顺序（按「先无行为变化、再统一口径」排）

| 步 | 动作 | 影响面 | 风险 |
|---|---|---|---|
| 1 | 把 `BillingHTTPClient` 从 App target 下沉到 `NetworkMonitorCore/Infrastructure/HTTP`，去掉默认参数里的 `AppContext.shared`（BillingProviderHTTP.swift:32） | 1 文件 + 6 个 provider 构造 | 零行为变化；但要先决定 Core 能否依赖 logger 注入 |
| 2 | 三个裸调 Core provider（Ollama / OpenDesign / OpencodeGo）改用统一 client，删掉各自 makeRequest/perform/errorMessage | 3 provider + 3 Models + 1 新文件 | **超时 20 → 15 要拍板**；Ollama 的两条路径、OpenDesign 的 401 清 workspace 缓存（OpenDesignBillingProvider.swift:172-175）需要 client 支持 per-endpoint 钩子 |
| 3 | UpdateChecker 改用统一 client（8 秒 + `.reloadIgnoringLocalCacheData` + GitHub 专属头变成 Endpoint 字段），保留 `UpdateCheckError` 作为该 Endpoint 的错误映射 | 2 文件 | 403 限流判定依赖 `X-RateLimit-Remaining`（:180），client 要把响应头透出 |
| 4 | 把 15 处收成 `Endpoint` 值 + `HTTPClient.send(_:)`，状态码 → 错误只留一份 mapper | 全量 12 个出网点 | 各 provider 的 403 话术不同（OpencodeGo「没订阅」、Cursor「Cookie 失效」），需要 mapper 允许 per-endpoint 覆写 |
| 5 | 在 client 里补 metrics（成功率 / 耗时 / status / 失败类别）与 URL 脱敏 | 1 文件 | 无 |
| 6 | 局域网 4 条 JSON 路由迁移；upload 保留独立客户端但复用 mapper 与脱敏 | 1-2 文件 | 中等：断点续传不能回归 |

### 6.3 影响面与阻碍

- **首要阻碍是 target 边界，不是代码量**：封装在 App、3 个调用方在 Core（BillingProviderHTTP.swift:2）。不先下沉，第 2 步做不了。
- **第二阻碍是单例**：Core 内 30 处默认参数直接绑 `AppContext.shared`（`grep '= AppContext\.shared' NetworkMonitorCore` → 30，全仓含 TestRunner 103）。新 client 只会再加一处；要真正「像组装组件一样」，默认参数这种隐式装配得先禁掉。
- **迁移规模**：与 HTTP 直接相关的文件 ≈ 16（6 封装 provider + 3 裸调 provider + 7 个 Models/Mapper + UpdateChecker + TransferHTTPClient + BillingProviderHTTP）。文件系统那 83 处本次不在范围内，但它是「外部世界」里最大的欠账。

---

## 未覆盖 / 待 leader 决策

1. 「15 处」与实测 17 个出网点的口径差：按 URLSession 实例算会更少，按请求发起点算是 17——建议统一按出网点。
2. 超时到底统一到 15 还是保留各家 20 / 8：需产品口径（Ollama 与 GitHub 的官方建议值我没验证）。
3. `NetworkMonitorUI`（61 文件、纯逻辑）本次未发现网络访问，确认属正常。
4. 文件系统 83 处与路径常量缺唯一真源，本报告只给计数与代表点，未逐个分类——建议另开一份审计。
