# 工程化横切面审计（toolbar / 一览）

> 只读审计。范围：质量门禁、测试体系、脚手架、可观测性、依赖与发布、文档体系。
> **不含**数据库 / 网络层内部实现（另有两路）。所有结论附 file:line 或命令输出。

---

## 1. 质量门禁矩阵

### 1.1 现在有什么

| 门禁 | 触发点 | 覆盖内容 | 证据 |
|---|---|---|---|
| 单文件体积（500 行 / 15360 B） | pre-commit + CI + release.sh | Sources/ 全部 .swift | `Scripts/git-hooks/pre-commit`；`ci.yml:60` `File size gate`；`release.sh:73` |
| 同族合计行数（只许变小） | **pre-commit + release.sh（CI 没有）** | 按类名前缀聚合 + 基线文件 | `pre-commit`（exec 到 check-file-families.sh）；`release.sh:74`；**`ci.yml` 全文无该步骤** |
| 发布说明生成器回归 | CI + release.sh + release.yml | compare 链接 / 逐条 hash / @提及 | `ci.yml:65`；`release.sh:75`；`release.yml` Release notes regression |
| debug 构建（含 test targets） | CI | 全量编译 | `ci.yml:73` |
| release 构建 | CI + release.yml | 生产方法误入 #if DEBUG 会红 | `ci.yml:78` |
| TestRunner 全量（--skip-build） | CI + release.sh | 178 个测试入口 | `ci.yml:83`；`release.sh:76-77` |
| 双架构 | CI 矩阵 + release 矩阵 | arm64 + x86_64 | `ci.yml:27-31`；`release.yml:32-38` |
| 产品架构自证（lipo） | release.yml | 交叉构建参数是否真生效 | `release.yml` Verify binary architecture |
| tag ↔ plist 版本一致 | release.yml（setup-build） | 防「发 1.20 却打旧包」 | `.github/actions/setup-build/action.yml` Version matches tag |
| 系统权限 API 白名单 | TestRunner（PermissionSourceGuardTests） | 直呼系统权限 API 的文件必须在白名单 | `Sources/TestRunner/PermissionSourceGuardTests.swift`（338 行） |

**唯一一条「依赖方向」性质的机器门禁就是 PermissionSourceGuardTests**，而它是靠读源码字符串的判断，不是编译期边界。

### 1.2 缺什么 + 本项目需不需要

| 缺口 | 现状证据 | 本项目需不需要 | 为什么 |
|---|---|---|---|
| 格式化（SwiftLint / SwiftFormat） | `ls .swiftlint.yml .swiftformat .swift-format` 全部 No such file（仓库根） | **需要（低优先）** | 11.5 万行 Swift，风格全靠 skill 人查。但项目已有强风格约定且 Swift 6 编译本身拦截大量问题，格式化只解决缩进/换行/import 排序。若引入，选 SwiftFormat 只跑「排版三件套」，不接全量规则集 |
| 静态分析（自定义规则） | 无 | **需要（只 3 条）** | 当前纯靠人守的硬规矩有 3 条：①禁 `print`（skill 第 7 条）——实测仍有 96 处，其中 2 处在设置页非探针位置（`SettingsAboutPane.swift:231,241`）；②禁直读 `UserDefaults.standard`；③Core/UI 禁 `import AppKit`（实测目前干净，但无人守）。这三条用 5 行 grep 脚本 + CI 即可，不需要 SwiftLint 全家桶 |
| 圈复杂度 | 无 | **需要（弱档）** | 现在唯一结构门禁是文件体积，500 行能被拆成 10 个 400 行文件绕过（families 门禁只堵同类名前缀）。复杂度门禁能堵住「小文件大函数」 |
| 重复代码 | 无 | **暂不需要** | Swift 生态 jscpd 类工具召回差；且本项目的重复主要来自「照抄上一次的模块」，正确解法是脚手架（§3）而不是检测 |
| 依赖方向 | 靠人 + skill 文字（`SKILL.md:29-37`） | **需要（不用工具）** | Core 不依赖 AppKit、UI 不依赖 AppKit/Core 是纯文本判据，一条 grep 门禁即可，成本近零 |
| 覆盖率 | CI 无任何 `--enable-code-coverage` / lcov（`grep 'code-coverage\|lcov' .github NetworkMonitor/Scripts` 空） | **需要「可见性」而非门禁** | UI 层主要靠离屏快照 + nmcli 验收（`docs/开发指南/UI-自动化-CLI.md`），行覆盖率会逼出虚假测试。建议只产 per-target 覆盖率报表，不设阈值 |
| dead code | 无 periphery 配置（`ls .periphery.yml` No such file） | **需要** | 1.29.0 一次性下线了「剪贴板分页 + 5 个死开关」（AGENTS.md「统一设置窗口」行），全靠人工盘点。periphery 可脚本化 |
| API 破坏检测 | 无 | **不需要** | 单 app、无外部消费者、不发布库；内部破坏由 Swift 编译直接报错 |

---

## 2. 测试体系

### 2.1 组织方式与规模

- `Sources/TestRunner/` **186 个 .swift / 22775 行**（`ls *.swift | wc -l` / `find . -name '*.swift' | xargs wc -l`）。
- 入口 `main.swift` **437 行**只做一件事：顶层顺序调用。手写断言辅助在 `AssertionHelpers.swift`（41 行，6 个函数）。
- 计数：全仓定义 `func run*Tests` **222 个**，`main.swift` 里直接调用 **178 个**（`grep -c 'Tests()' main.swift`）。差的 44 个不是死测试——已逐个核对，它们由上层测试函数内部调用（例：`SystemMetricsTests.swift:7` 的 `runSystemMetricsTests()` 末尾调 Supplement 子套件；`ClipboardCapacityTests.swift:15` 调 `runCapacityByteCountTests()`）。

### 2.2 四个评估项

**① 新加一个模块要登记几处？**
- 写 `XxxTests.swift` + 在 `main.swift` 加一行调用 = **2 处**（1 处是新增文件，1 处是中心清单）。
- 但 `main.swift` 已 437 行，门禁线 500 行 → **只剩 63 行余量**，约 60 个新入口就撞墙。这是「加测试就要先拆 main.swift」的结构性摩擦。

**② 能不能表驱动 + 自动发现？**
- Swift 无法反射发现顶层函数，`@main` 也不能自动扫描。可行且有先例的模式：**protocol + 静态注册表**——
  `protocol TestSuite { func run() }`，每个 `*Tests.swift` 末尾 `static let suite: TestSuite = ...`，注册表 `TestSuiteRegistry.all` 用一行 `grep 'static let suite' Sources/TestRunner | sort` 生成（可脚本化、可 CI 校验未登记项）。
- 现状的反例代价：`PanelTabCatalogTests.swift:49` 这种「冻结 live id 集合」的断言，配合 178 行手工清单，任何结构调整都要人肉对表。

**③ 199 个 run*Tests 的命名 / 断言一致性**
- 命名：`run<Domain>Tests` 高度一致（222/222 都是该形态）。
- 断言：**只有 6 个**辅助（`AssertionHelpers.swift`：assertEqual / assertNotNil / assertContains / assertNotContains / assertThrows / assertInvalidResponse）。
- 关键缺陷：`assertEqual` 失败即 `exit(1)`（`AssertionHelpers.swift:9-20`）——**第一个失败终止整个套件，一次只能看到一个红**。修复一处、跑一次、再看下一个，与「组装式快速迭代」直接冲突。

**④ 测试密度最低的目录（Top 10）**

> 口径：`srcFiles` = 该目录下 maxdepth 1 的 .swift 数；`testRefs` = TestRunner 里**文件名匹配关键词**的测试文件数。
> **这是近似排序口径，不是精确 file→test 映射**（TestRunner 是平铺的，无目录镜像），仅用于找出盲区，不能当作覆盖率读数。

| # | 目录 | srcFiles | testRefs | 比值 |
|---|---|---|---|---|
| 1 | NetworkMonitor/MenuPanel | 104 | 8 | 0.08 |
| 2 | NetworkMonitor/Debug | 54 | 6 | 0.11 |
| 3 | NetworkMonitor/Settings | 60 | 11 | 0.18 |
| 4 | NetworkMonitor/DrawnUI | 14 | 3 | 0.21 |
| 5 | NetworkMonitorUI | 60 | 13 | 0.22 |
| 6 | NetworkMonitorCore/Notifications | 15 | 6 | 0.40 |
| 7 | NetworkMonitorCore/Appearance | 4 | 2 | 0.50 |
| 8 | NetworkMonitorCore/Infrastructure | 24 | 14 | 0.58 |
| 9 | NetworkMonitor/Permissions | 5 | 3 | 0.60 |
| 10 | NetworkMonitor/SystemMetrics | 14 | 9 | 0.64 |

对照组（密度健康）：`NetworkMonitor/Billing` 8/24 = 3.0、`NetworkMonitor/Snip` 32/32 = 1.0、`NetworkMonitorCore/Token` 8/15 = 1.9。

**结论**：盲区集中在 **MenuPanel（104 文件）/ Settings（60）/ Debug（54）/ NetworkMonitorUI（60）**——也就是「组装式开发最常新增东西的地方」恰恰测试最薄。其中 MenuPanel 与 Settings 的验收主要靠 nmcli 场景（`nmcli` 16 个源文件，`Scenario.swift` 的 `panel-tour`）与离屏快照，属于**另一条验收通道**，不应简单判为「没测试」。

---

## 3. 模板化 / 脚手架

### 3.1 现状：零脚手架

`NetworkMonitor/Scripts/` 17 项，全是构建 / 取证 / 发布 / 门禁：`build-app.sh`、`check-file-size.sh`、`check-file-families.sh`、`release.sh`、`generate-release-notes.sh`、`test-release-notes.sh`、`perf-hotspot-sample.sh`、`generate-icon.swift`、`clipboard-*` 探针、`measure-*.py`。
仓库根无 `Makefile` / `Justfile`。全仓 `*template*` 命中的只有 `.open-design/`（原型模版）与 `.github/PULL_REQUEST_TEMPLATE.md`（PR 模板）。
**没有任何「新增模块 / 页面 / provider / 事件处理器」的生成器或模板。**

### 3.2 新增一类东西现在必须做的事（照抄 + grep 全仓，无清单）

**A. 新增 Billing provider —— 5 处**
1. 实现协议：`NetworkMonitorCore/Billing/BillingProvider.swift:9`（`id / displayName / symbolName / supportsModelBreakdown / supportsTimeSeries / supportsUsage` …），放 `Billing/` 或 `Billing/Providers/`
2. 注册：`NetworkMonitor/AppCoordinator.swift:136` 的 `billingKinds` 数组加 `(kindID, title, make)` 三元组
3. 若新窗口种类：`BillingQuotaWindow` / `BillingWindowKindInventory`
4. 测试：TestRunner 加解码 / 失败路径（参考 `BillingDecodingTests.swift` 277 行、`BillingProviderFailureTests.swift`）
5. 文档：`AGENTS.md` 「计费额度查询」行 + `docs/设计/` 一份设计规格

**B. 新增设置分类 —— 5 处**
1. `NetworkMonitor/Settings/SettingsSection.swift`（**4 个 `switch self`**：title / icon / stableKey / 说明，:23/:40/:57/:74）
2. `NetworkMonitorUI/SettingsSkeletonLogic.swift:81` 的 `SettingsSectionID`
3. `SettingsSkeletonLogic.swift:113` 的 `SettingsSidebarLayout.groups`（三段分组）
4. `NetworkMonitor/AppCoordinator+Settings.swift:17` 的 `factories` 字典（现 11 项）+ 新 Pane 文件（Settings/ 下已有 27 个 `*Pane*` 文件）
5. `AGENTS.md` 「统一设置窗口」行的「十一分类」文案 + `TestRunner/SettingsThemeTests.swift`

**C. 新增面板分页 —— 6 处**
1. `NetworkMonitor/MenuPanel/MenuTabBarView.swift:14` `MenuPanelTab`（含 title / stableID 等 **3 个 `switch self`**）
2. `NetworkMonitorUI/PanelTabCatalog.swift:15` `stableIDs`
3. `NetworkMonitor/MenuPanel/MenuPanelView+Panes.swift:51` 分派
4. `MenuPanelController` 懒装配 + 转发（`MenuPanelController.swift:223,230,246` 等多处）
5. `TestRunner/PanelTabCatalogTests.swift:21,49`（硬编码「剩 5 个分页」与冻结 id 集合，**加/删分页必红**）
6. 偏好迁移：`PanelTabCatalog.legacyRawValueToStableID`（已在 1.29.0 因下线剪贴板分页付过一次代价）

**D. 新增 Hook 事件处理器 —— 现状：无法执行，规范已幽灵**
`SKILL.md:34` 与 `:59-60` 写明「`ReasonixHookMonitor` → `HookEventDispatcher` → `HookEventHandler`；新增事件处理 = 实现协议 + `dispatcher.register`」。
实测：`grep -rin 'reasonix' --include='*.swift' Sources/` **零命中**；`grep -rin 'hook' Sources/NetworkMonitor Sources/NetworkMonitorCore | grep -vi 'hotkey\|hookdata\|apphook'` **零命中**。
→ **这套 SPI 在代码里已不存在**（Token 页改造后成为死规范）。这是本审计里最严重的一条文档/代码脱节。

**E. 新增通知事件 —— 6 处**
1. `NetworkMonitorCore/Notifications/NotificationEvent.swift:13` 加 case
2. 同文件 `label` 与 \`NotificationEvent.forBillingKind\` 类映射
3. `NotificationCue`（`NotificationCue.swift:10`，内建合成音按 cue 音色族，`CueSoundSynth`）
4. `NotificationPreferences.swift:66`（`notify.<rawValue>.<field>` 键）
5. 设置页挂 `SettingsNotificationEventCard`（5 处现成用法：ProvidersPane:73 / ClipboardPane:74 / CapturePane:82 / TransferPane:47 / GeneralPane:67）
6. `TestRunner/NotificationTests.swift:21` **硬编码 `allCases.count == 7`** → 加事件必红，且 `SoundStoreTests.swift:58` 也遍历 allCases

### 3.3 照抄会漏什么

- 漏「偏好迁移」：`PanelTabCatalog.legacyRawValueToStableID` 与 `BillingInstance` 的「默认实例沿用旧键」是**上线后才补的**（AGENTS.md 明写「零迁移」诉求），照抄新代码抄不到这一层。
- 漏「冻结断言」：`PanelTabCatalogTests:49`、`NotificationTests:21` 是硬编码计数，抄漏就静默通过。
- 漏「懒装配」：面板页必须在 `MenuPanelController` 的懒装配表里注册，否则页签在但切过去空白（`docs/踩坑/运行时/菜单面板内存常驻.md`）。

---

## 4. 可观测性

### 4.1 日志链路（已成形）

- 协议：`NetworkMonitorCore/Domain/Protocols/LoggingService.swift:16`（log/debug/info/warning/error）。
- 实现：`OSLogLogger`（`Infrastructure/Logging/Loggers.swift:10`，**一律 `%{public}@`**，默认 `minLevel = .info`）+ `ConsoleLogger`（print，测试/开发）。
- 脱敏：`LogRedaction`（`Infrastructure/Logging/LogRedaction.swift`）提供 `path` / `paths` / `pin` / `secret`，背景文档 `docs/踩坑/运行时/OSLog的public字段全本机可读.md`。
- 采用度：`logger.{error,warning,info,debug}` 调用 **498 处**；残留 `print(` **96 处**（`grep print | grep -v ConsoleLogger | wc -l`），其中 94 处在 `NetworkMonitor/Debug/`（各 probe 属正常），**2 处在产品代码** `Settings/SettingsAboutPane.swift:231,241`（`[update-probe]`，违反 skill 第 7 条）。
- 生产可观测性已修过一次：`docs/踩坑/构建/生产日志不可观测.md` 记录了「LaunchServices 启动的 .app 丢弃 stdout」→ 组合根改注入 `OSLogLogger`。

### 4.2 有没有统一 metrics？——**没有**

`grep -rn 'successRate\|latency' Sources/NetworkMonitorCore Sources/NetworkMonitorUI` → **零命中**。
只有两处局部重试账本，不是全局指标：`ClipboardOCRPolicy.failureCount`（:104）、`ClipboardThumbnailRetryPolicy.failureCount`（:48）。
**没有「成功率 / 耗时 / 失败原因」三元组**，也没有任何计数器 / 直方图 / 采样汇总出口。

### 4.3 MainThreadWatchdog 覆盖到哪？——**只覆盖菜单面板**

- 口径：`NetworkMonitorCore/Infrastructure/MainThreadWatchdogPolicy.swift:13-15`（0.5 s tick / 2 s 阈值），日志正文含分页 / 展开态 / 索引状态并过 `LogRedaction.paths`。
- 装配：`NetworkMonitor/MenuPanel/MenuPanelController.swift:179` `watchdog.start()`，心跳在 `MenuPanelController+Open.swift:90` `beat(...)`。
- **未覆盖**：设置窗口、剪贴板浮层、截图覆盖层、局域网互传服务、Token 索引后台。这些路径卡住时没有对应探针（UNIX 层面仍是 `OSLog` 里什么都没有，见 `docs/踩坑/运行时/面板未响应…md` 的事故记录）。

### 4.4 崩溃上报——**零**

`grep -rn 'NSSetUncaughtExceptionHandler\|signal(SIG\|atexit\|MetricKit' Sources/` → **零命中**。
ad-hoc 签名 + 无崩溃收集 = 用户机器上的崩溃**不留任何应用侧痕迹**，只能靠系统 `~/Library/Logs/DiagnosticReports` 人肉找（且进程名是中文「一览」，排查时容易被忽略）。

### 4.5 「线上出问题能不能定位」评估

| 问题类型 | 能否定位 | 依据 |
|---|---|---|
| 面板主线程卡顿 | **能**（唯一做全的一条） | 看门狗 2 s 阈值 + 上下文日志 |
| 某个 provider 查询失败 | **部分**（有 error 日志，无成功率/耗时趋势） | 498 处 logger，但无 metrics |
| 设置窗 / 剪贴板 / 截图 / 互传卡住 | **不能**（无探针） | 看门狗只挂在 MenuPanelController |
| 崩溃 / 闪退 | **不能**（应用侧零痕迹） | 无异常/signal 处理器 |
| 性能回潮 | 部分（手动脚本） | `Scripts/perf-hotspot-sample.sh` 有基线（主线程 ≤1.5% / footprint ≤160 MB），但需人工跑 |

结论：**「有日志可查、无指标可看、无崩溃可追、探针只罩住一个面板」**。

---

## 5. 依赖与发布

### 5.1 零第三方依赖

`NetworkMonitor/Package.swift` 五个 target（Core / UI / App / TestRunner / nmcli）全部无 `.package(...)` 依赖；`Package.resolved` 不存在。
⚠️ 但 `NetworkMonitor/.build/checkouts/Charts/` 存在——**历史依赖残留**（Package.swift 已无引用），属构建缓存垃圾，不影响正确性，可安全清理。

### 5.2 版本号定义在几处

| 位置 | 角色 | 证据 |
|---|---|---|
| `NetworkMonitor/Scripts/build-app.sh:245`（`CFBundleShortVersionString` = 1.29.0）+ `:244`（`CFBundleVersion` = 22） | **唯一真源**（内联 Info.plist，仓库无独立 plist 模板） | `setup-build/action.yml` 注释明写「版本号唯一真源是 build-app.sh 里的内联 Info.plist」 |
| `AGENTS.md:4` | 人类可读副本 | `release.sh:108-115` 的 python 同时改 plist 与 AGENTS.md |
| `NetworkMonitor/dist/一览.app/Contents/Info.plist` | 构建产物（gitignore） | — |
| 代码侧 | **全部从 `Bundle.main` 读，无硬编码** | `SettingsAboutPane.swift:217`、`AppCoordinator+Update.swift:49`、`AppCoordinator+Transfer.swift:12` |

### 5.3 版本号漂移风险点（3 个）

1. **`CONTRIBUTING.md:41-45` 仍是人肉三步**（改 build-app.sh + AGENTS.md → 推 main → 打 tag），与已自动化的 `Scripts/release.sh`（校验→bump→提交→推→打 tag→跟 CI）不一致；新人照 CONTRIBUTING 做会漏门禁与 CI 闸门。
2. **`NetworkMonitor/agent.md:46` 内嵌一份过时 plist 模板**（`CFBundleShortVersionString` = `1.0`、bundle id = `com.example.NetworkMonitor`、无 `CFBundleDisplayName`）。这是**会误导人照抄的活文档**，且与 AGENTS.md 的 bundle id `com.bsfeng.yilan` 冲突。
3. `docs/开发指南/构建与测试.md:72` 描述「改版本号 + 打 tag」人肉流程，未指向 `release.sh`（`docs/索引.md` 全文 **0 次**提及 release.sh；README **0 次**）。

### 5.4 签名现状

**全部 ad-hoc**（`docs/发版记录.md:100-104`：仓库未配置 `BUILD_CERTIFICATE_BASE64`，`setup-build` 跳过导入，`build-app.sh` 回落 ad-hoc）。
后果：每次重建 cdhash 变化 → TCC 授权（辅助功能 / 屏幕录制 / 输入监控）全部需要重授；这也是「钥匙串不做默认凭据后端」的原因（`SKILL.md` 第 5 条 / `docs/踩坑/运行时/自签名App读钥匙串卡死.md`）。

### 5.5 release.yml 发布矩阵与校验项

- 矩阵：`arm64 → macos-26`、`x86_64 → macos-26-intel`（`release.yml:32-38`），`fail-fast: false`，超时 40 分钟。
- 校验项（完整）：工具链展示 → 证书导入（可选）→ **tag ↔ plist 一致性** → 构建+签名+打包（`BUILD_SYSTEM=default`、`SKIP_INSTALL=1`、按 ARCH 交叉）→ **lipo 架构自证** → `codesign -dv` 展示 → `ditto` 打 zip（URL 友好名 `Yilan-<arch>.app.zip`）→ 上传 artifact。
- publish job：download-artifact（merge）→ **release notes 回归** → 生成（失败降级不阻断）→ `softprops/action-gh-release@v2` 建 release（两架构合并进同一 release，规避 422）。

---

## 6. 文档体系

### 6.1 组织

- 导航：`docs/索引.md`（25 KB，唯一入口，AGENTS.md 指向它）。
- 分层：`docs/开发指南/`（5 篇：构建与测试 / 提交规范 / 文档规范 / UI-自动化-CLI / 快照冻结通道）、`docs/设计/`（**27 篇**）、`docs/调研/`（17 篇）、`docs/踩坑/`（按 `构建 / 运行时 / 接口 / swift-并发` 四域，44 篇，有 `README.md` 索引）、`docs/发版记录.md`。
- `AGENTS.md`（21.7 KB）是会话自动注入入口；`CONTEXT.md`（10 KB）术语表；`CONTRIBUTING.md`、`README.md`（18.8 KB）。
- **无 doc 生成**（无 jazzy / docc / DocC catalog，`grep 'jazzy\|docc' Package.swift .github Scripts` 空）。

### 6.2 「新加一个模块要更新哪些文档」——**纯靠人记，无机制**

- `docs/开发指南/文档规范.md:10,17,38` 只要求「新增**文档**必须同步索引」「文档不得孤立」——**方向是「文档→索引」**。
- **反向链条（代码 → 哪些文档必须改）完全不存在**：没有清单、没有 CI 检查、没有 doc lint、没有 generator。
- 实际承担这一职责的是 `AGENTS.md` 的功能模块大表（21.7 KB 里极密集的「模块 → 行为」长句），全靠人手工续写。而 `文档规范.md:22` 要求「AGENTS.md 必须精简」——**这条规范已被自身实践证伪**（21.7 KB 不精简）。

### 6.3 文档与代码脱节的已知点（抽查 5 条，全部命中）

| # | 文档声称 | 实际 | 证据 |
|---|---|---|---|
| 1 | `SKILL.md:34,59-60`：`ReasonixHookMonitor → HookEventDispatcher → HookEventHandler` 是可插拔 SPI，「新增事件处理 = 实现协议 + register」 | 代码里**不存在**（零命中） | `grep -rin 'reasonix' Sources/` 空；`grep -rin 'hook' Sources/NetworkMonitor{,Core}`（排除 hotkey/hookData）空 |
| 2 | `SKILL.md:12`：「SwiftPM **四**目标」 | `Package.swift` 有**五**个 target（另有 `nmcli`） | `Package.swift` targets 数组 |
| 3 | `docs/开发指南/构建与测试.md:65,71`：runner 是 `macos-15` / `macos-15-intel` | 实际 `macos-26` / `macos-26-intel` | `ci.yml:27-31`、`release.yml:32-38` |
| 4 | `CONTRIBUTING.md:15-16`：`swift run --disable-sandbox TestRunner` / `swift build --disable-sandbox` | 本机只装 CLT 时**缺 `--build-system native` 直接失败** | `docs/踩坑/构建/swift-build-会话初始化失败.md`；skill 与 docs/构建与测试.md 都带该参数 |
| 5 | `NetworkMonitor/agent.md:46`：plist 模板 `CFBundleIdentifier = com.example.NetworkMonitor`、版本 `1.0` | 实际 `com.bsfeng.yilan`、`1.29.0` | `build-app.sh:244-245`、AGENTS.md |

补充：`docs/开发指南/构建与测试.md:90` 说「新增测试：编辑 `Sources/TestRunner/main.swift`」——与实际「每域一个 `*Tests.swift` + main 一行登记」的现状一致，但没写 `main.swift` 已 437 行、贴 500 行门禁线这一约束。

---

## 7. 结论：缺口排序（按对「组装式开发」的阻碍程度）

| # | 缺口 | 补什么 | 大致怎么做 | 可脚本化 |
|---|---|---|---|---|
| **1** | **扩展点无清单 + 存在幽灵 SPI** | 一份「扩展点登记表」：provider / 设置分类 / 面板分页 / 通知事件 / 处理器，逐项列「必须改的文件:行 + 必须补的测试 + 必须更新的文档」；并**删除或重建** `SKILL.md` 里的 Hook SPI 章节 | 新建 `docs/开发指南/扩展点清单.md`，用 grep 反查生成初稿后人工确认；SKILL.md:34/59-60 二选一：写入真实 SPI 或不写 | ✅ 初稿可脚本生成（grep 注册点），维护需人 |
| **2** | **零脚手架** | 4 个生成器：`new-billing-provider.sh` / `new-settings-pane.sh` / `new-panel-tab.sh` / `new-notification-event.sh` | 每个脚本按 §3.2 的清单打补丁（模板文件 + sed 插注册行 + 打印「还需人工做的事」），放 `NetworkMonitor/Scripts/scaffold/` | ✅ 完全可脚本化，收益最高 |
| **3** | **测试登记中心化 + 首错即停** | ①`TestSuite` protocol + 静态注册表（生成式，替代 178 行手写清单）；②`assertEqual` 改为累计失败、末尾汇总 `exit(1)` | ①改造 `AssertionHelpers.swift` + 新增 `TestSuiteRegistry`；②把 `exit(1)` 换成 `failures.append`（约 20 行） | ✅ 注册表生成与断言改造都可脚本化 |
| 4 | 门禁矩阵不完整 | ①CI 补 `check-file-families.sh`；②加 3 条 grep 门禁（禁 print / 禁直读 UserDefaults / Core 禁 import AppKit）；③加圈复杂度弱档 | ①`ci.yml` 加一步；②`Scripts/check-forbidden-patterns.sh`；③复杂度可用 `swiftlint` 单条规则或自写 awk 统计 | ✅ 全部可脚本化 |
| 5 | 可观测性无指标、无崩溃、探针范围窄 | ①`MetricsService`（计数 + 耗时直方图，出口走 OSLog）；②`NSSetUncaughtExceptionHandler` + 关键 signal；③看门狗从 MenuPanelController 提到 AppCoordinator（全局一个） | ①新增协议 + 在 provider / 传输 / 索引三处埋点；②AppDelegate 一处 20 行；③`MainThreadWatchdog` 已是独立类，改持有位置即可 | 🟡 部分 |
| 6 | dead code / 重复无检测 | 接 `periphery` 出报告（不设门禁，先看数） | `brew install periphery`；CI 加 `periphery scan --format json` 只出报告 | ✅ |
| 7 | 格式化缺失 | SwiftFormat 只跑排版（indent / linebreaks / imports），不接全量规则 | 加 `.swiftformat` + pre-commit 一步 | ✅ |
| 8 | 覆盖率不可见 | 产出 per-target 覆盖率报表，不设阈值 | `swift test --enable-code-coverage` 不适用于自研 TestRunner → 用 `llvm-cov` 对 TestRunner 二进制 `--instr-profile` 取数 | 🟡 需验证 |
| 9 | 文档与代码脱节无机制 | ①修正 §6.3 的 5 条；②给 `AGENTS.md` 的「模块表」加末列「对应源目录」，可 grep 校验目录存在 | 写 `Scripts/check-docs-links.sh`：抽 AGENTS/docs 里的路径，逐个 `test -e` | ✅ |
| 10 | API 破坏检测 | **不做** | 单 app 无外部消费者 | — |

### 哪 3 条「不做则组装式开发根本无从谈起」

1. **#1 扩展点清单 + 幽灵 SPI 清理**——现在新增任何一类东西都要全仓搜索，且规范里指的那套 SPI 已经不存在。没有清单，「组装」就是「考古」。
2. **#2 脚手架生成器**——这是用户诉求（「像组装组件一样，只实现功能」）的直接落点。四类高频扩展各需 5–6 处机械改动且必须同步改测试硬编码与偏好迁移，人工照抄必然漏项。
3. **#3 测试登记去中心化 + 断言不再首错即停**——`main.swift` 只剩 63 行余量、178 行手写清单、一次只能看一个红。不解决这一条，任何「新装一个组件并验证它」的循环都跑不动。

---

## 未覆盖项（本轮没查）

- 数据库 / 网络层内部实现（按任务约定交给另两路）。
- 实际构建 / 测试执行（任务规定禁止，leader 独占）——因此所有耗时、通过率、真实覆盖率数值均为**未测量**。
- `docs/设计/` 27 篇与 `docs/调研/` 17 篇的逐篇内容一致性（只抽查了 5 条命令/事实类脱节）。
- CI 实际运行历史与耗时（未查 GitHub Actions 记录）。
- `nmcli` 16 个源文件的命令实现与 `docs/开发指南/UI-自动化-CLI.md` 的逐条对照（只抽样看了命令表存在）。
