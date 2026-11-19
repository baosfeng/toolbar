# 数据持久化层架构审计（只读）

> 审计对象：`NetworkMonitor/Sources`（SwiftPM 五 target）。
> 判「违反」以 `.agents/skills/toolbar-coding-standards/SKILL.md` 为准。
> 本次只读：未构建、未跑测试、未改任何既有文件。所有行号为审计当时快照。
> 时间：2026-11-19。

---

## 0. 一句话结论

**不是「统一数据库 / HTTP 接口」的问题——本项目已经有统一 SQLite 通道，问题在「通道太底层」。**
仓储协议把 `sqlite3` 的裸指针语义（队列/deadlock/事务）漏给了装配层，于是「加功能」仍需字节级懂库；
真正的抽象缺口是 **①无事务 API ②错误被静默吞掉 ③迁移无统一登记表 ④能力探测靠 downcast 拼装**。

评分（10 分制，审计者主观）：

| 维度 | 分 | 说明 |
|---|---|---|
| 调用面收口 | 8 | App/UI 目标**零 SQLite 依赖**，UI 不碰 SQL |
| 事务完整性 | 4 | 无显式事务 API，3 处业务动作跨事务 |
| 协议粒度 | 5 | 剪贴板一族被机械拆成 5 协议 + 3 处运行时 downcast |
| 迁移可扩展 | 6 | 有版本阶梯，但无统一登记表、双轨制 |
| 表 owner 清晰 | 6 | `clipboard_items` 有 7 个写入方 |
| 错误可观测 | 3 | `query(sql:)` / `clipExec` 静默返回 |

---

## 1. 绕过面：不经过仓储协议直接碰数据库

### 1.1 先说结论：**UI / 控制器层没有绕过面，绕过面全在 Core + 装配层**

证据（命令 + 输出）：

```
$ cd NetworkMonitor/Sources && grep -rln 'import SQLite3' --include='*.swift' ./NetworkMonitor ./NetworkMonitorUI
(空输出)            ← App 目标与 UI 目标完全不 import SQLite3
$ grep -rn 'AppContext.shared.database' --include='*.swift' .
(空输出)            ← 没有通过全局单例偷偷拿库
$ grep -rnE 'SELECT |INSERT |UPDATE |DELETE FROM ' --include='*.swift' ./NetworkMonitor ./NetworkMonitorUI | grep -v '//'
./NetworkMonitor/Debug/ClipboardPerfProbe.swift:57: "SELECT id, content_hash FROM clipboard_items ORDER BY created_at DESC LIMIT 20;"
```

- 唯一命中是**夹具字符串**（压测样本正文），不是执行语句 → **UI 层 SQL 数 = 0**。
- App 层对数据库的全部访问都经 `repository.xxx()`：13 个方法、21 处调用（`repository.fetchAllClipboardItems(` 5 次最多）。
- 仓储协议无裸指针泄漏：`OpaquePointer` 在 `NetworkMonitor/` 只出现在 IOKit 读数器（GPU/温度），与数据库无关；`NetworkMonitorCore/Domain` 里零命中。

### 1.2 真实绕过面分类计数

| # | 类型 | 数量 | 具体 | 证据 |
|---|---|---|---|---|
| A | **装配层强制 downcast**（同一实例多协议，靠 `as?` 取能力） | **4** | 板 / Token / 批量删 / 容量清理 | 见下表 |
| B | **Core 内部绕过自身协议**（`DatabaseManager` 扩展互调具体类型方法，不经 `any ClipboardRepository`） | **1** | `ClipboardCapacityPruneStore` 自调 `fetchAllClipboardItems` / `deleteClipboardItems` | `ClipboardCapacityPruneStore.swift:19,25` |
| C | **具体类直接被构造** | **1 处**（唯一） | `DatabaseManager()` | `AppCoordinator.swift:103`（组合根，**合规**） |
| D | **视图/控制器直接 query(sql:)** | **0** | — | 见 1.1 命令 |
| E | **自己拼 SQL（App 层）** | **0** | — | 同上 |

A 类的四个探测点：

```
ClipboardLimitPruner.swift:60        let capacity = repository as? any ClipboardCapacityPruneRepository
ClipboardImageGC.swift:99            guard let capacity = repository as? any ClipboardCapacityPruneRepository
ClipboardSelectionActions.swift:126  if let batch = repository as? any ClipboardBatchDeleteRepository
AppCoordinator+Clipboard.swift:65    boardRepository: database as? any ClipboardBoardRepository
AppCoordinator+Settings.swift:62     let store = self.database as? any HarnessTokenRepository
```

**典型 3 例（按危害排序）**：

1. `ClipboardSelectionActions.swift:126` —— 多选删除**静默退化**：
   拿到 `any ClipboardRepository`，`as?` 失败就逐条 `deleteClipboardItem`（N 个事务）。
   类型系统不报错，行为差 N 倍。
2. `ClipboardLimitPruner.swift:60` —— 容量清理**静默跳过**：downcast 失败直接 `return []`，
   上层以为「没有超限条目」，实际是「这条能力没接上」。
3. `AppCoordinator+Clipboard.swift:65` —— 板能力靠 `database as? any ClipboardBoardRepository` 拼装，
   `ClipboardBoardCoordinator` 的 `repository` 因此是 `Optional`（`:20`），板功能整条链路都被迫处理「可能没有板能力」。

> 这 4 处是**同一个设计缺陷的症状**：ISP 把协议切碎了，但实现永远是同一个 `DatabaseManager`，
> 装配层只好用 `as?` 把碎协议再拼回去。→ 见第 2 节。

---

## 2. 仓储协议清单

### 2.1 全表

| 协议 | 方法数 | 实现文件 | 调用方（`any X`，不含 TestRunner） |
|---|---|---|---|
| `DatabaseService` | 4（isReady/initialize/initializeInMemory/close/**query(sql:)**） | `DatabaseManager.swift` | **0 直接** —— 只作为 `AppDatabase` 的组合成分被继承 |
| `AppDatabase`（typealias） | = DatabaseService & ClipboardRepository & ClipboardOCRRepository | — | **4**（AppCoordinator / +Clipboard / ClipboardOCRSetup） |
| `ClipboardRepository` | **13** | `DatabaseManager+ClipboardRepository.swift`(308行) + `ClipboardItemEditRepository.swift`(编辑) + `DatabaseManager+ClipboardSearch.swift` | **19** |
| `ClipboardOCRRepository` | **1** | `ClipboardOCRStore.swift`(36行) | **2** |
| `ClipboardBoardRepository` | **6** | `ClipboardBoardRepository+SQLite.swift` | **4** |
| `ClipboardBatchDeleteRepository` | **1** | `ClipboardBatchDeleteStore.swift`(33行) | **2**（其中 1 个是注释） |
| `ClipboardCapacityPruneRepository` | **2** | `ClipboardCapacityPruneStore.swift`(32行) | **3**（其中 1 个是注释） |
| `HarnessTokenRepository` | **9** | `Harness/HarnessUsageIndexStore.swift` + Aggregation + Purge（同族 3 文件） | **6** |

**全部 8 个协议，实现方只有 `DatabaseManager` 一个类**（`grep 'extension DatabaseManager: '` 命中 6 个，加上 `DatabaseService` 在类声明处、`HarnessTokenRepository` 在 Store 文件）。

### 2.2 「一个类被机械拆成 6 个协议」——**剪贴板这一族成立，但动机不是 SRP，是行数门禁**

**判据**：同因变化？——剪贴板条目 / 板 / OCR / 批量删 / 容量清理**共享同一张表 `clipboard_items`、同一份 schema、同一条写队列、同一份列映射**。
表结构一改，这 5 个协议里有 4 个要动；队列模型一改，5 个全动。→ **它们同因变化，拆开没有换来独立性。**

拆分的真实动机在代码里写得明明白白：

```
ClipboardBatchDeleteStore.swift:6-7      独立成文件：同族门禁按类名前缀聚合行数，多选删除是新领域，
                                          塞进 DatabaseManager+ClipboardRepository.swift 只会撑大既有族
ClipboardCapacityPruneStore.swift:5-6     同上
ClipboardItemEditRepository.swift:11-12  文件命名刻意不像其他仓储文件那样带 DatabaseManager+ 前缀：
                                          同族门禁按类名前缀聚合，那样会把本批增长记到已顶到基线的 DatabaseManager 族上
```

**这是「为了过门禁而改名 / 拆协议」的直接书面证据**——门禁在推动形状，而不是职责在推动形状。
（同一处注释还说明：改名是为了让门禁**看不见**这部分增长，属于度量规避，建议 leader 单独处置。）

**真有多个变更原因的**（这部分拆分是对的）：

| 协议 | 独立变更轴 | 判断 |
|---|---|---|
| `HarnessTokenRepository` | 索引 schema + 增量判据（size/mtime）+ 聚合口径 | ✅ 真领域，与剪贴板零耦合 |
| `ClipboardBoardRepository` | 板（分组）语义，独立表 `clipboard_boards` | ⚠️ 半真：有自己的表，但条目表也被它写（`moveItemToBoard` / `deleteBoard`） |
| `ClipboardOCRRepository` | 异步回写，生命周期独立 | ❌ 协议只有 1 个方法（`UPDATE ... ocr_text`），1 调用方，拆出来的收益 < 装配成本 |

### 2.3 过度抽象风险（只有 1 个实现且短期不会有第二个）

- `ClipboardOCRRepository`（1 方法 / 1 调用方 / 1 实现）
- `ClipboardBatchDeleteRepository`（1 方法 / 1 真实调用方）
- `ClipboardCapacityPruneRepository`（2 方法 / 2 真实调用方）
- `DatabaseService.query(sql:handler:)` —— **协议里唯一的通用查询口，生产代码零调用**（见 §3.1），
  只有注释在警告它带来的死锁风险。这是「协议里躺着一条没人用、但谁都能用的逃生通道」。

> 注意：这三个小协议**不是为 mock 服务的**——TestRunner 里 `MockClipboardRepository`(1) / `RecordingCapacityRepository`(3) / `CountOnlyRepository`(3) 确实是测试替身，
> 所以「有测试价值」成立；但它们本可以作为 `ClipboardRepository` 的**默认实现或无协议扩展**存在，不必各占一个协议 + 一处 downcast。

---

## 3. 事务与并发

### 3.1 读写路径

```
写：serialQueue.sync { db }                    ← DatabaseManager.swift:36（DatabaseQueue，200ms 排队告警）
读：withReadDB(fallback) { db }               ← DatabaseManager.swift:244-256
      ├─ readDB != nil → readQueue.sync（SQLITE_OPEN_READONLY 独立连接，:127）
      └─ readDB == nil → serialQueue.sync（内存库 / 只读连接打不开时退化）
PRAGMA：journal_mode=WAL(:112)、mmap_size=0(:110/135)
```

- 写队列 / 读队列**双连接 + WAL**，读不排写后面（2026-11 面板未响应事故的修复）。
- `query(sql:handler:)`（:215）**永远走写队列**，`_query`（:221）里 `sqlite3_prepare_v2` 失败直接 `return`（:226-228）——**静默失败，无日志**。

队列直接使用点分布（`serialQueue.sync` / `withReadDB` 计数）：

| 文件 | 写 | 读 |
|---|---|---|
| `DatabaseManager.swift` | 6 | 1 |
| `DatabaseManager+ClipboardRepository.swift` | 6 | 6 |
| `ClipboardBoardRepository+SQLite.swift` | 4 | 3 |
| `HarnessUsageIndexStore.swift` | 2 | 1 |
| `HarnessUsageIndexPurge.swift` | 1 | 1 |
| `HarnessUsageIndexAggregation.swift` | 1 | 2 |
| `ClipboardOCRStore.swift` / `ClipboardItemEditRepository.swift` / `ClipboardBatchDeleteStore.swift` | 各 1 | 0 |

→ **9 个文件、23 处手工 `serialQueue.sync`**。没有任何一处是「表/实体级」入口，全是「方法级自己开队列」。

### 3.2 有没有显式事务 API？——**没有**

```
$ grep -rnE 'func (withTransaction|inTransaction|transaction|performTransaction)' --include='*.swift' .
(空输出)
```

事务是**手写字符串**，共 6 个文件 20 处 `BEGIN/COMMIT/ROLLBACK`：

```
HarnessUsageIndexStore.swift:108,113,117,121,124,125
HarnessUsageIndexAggregation.swift:268,271,275,276
HarnessUsageIndexPurge.swift:34,47,53,57,58
ClipboardItemEditRepository.swift:46,52,53
DatabaseManager+ClipboardRepository.swift:206,211,219,229,234,235   (updateClipboardStackPositions)
DatabaseManager+ClipboardRepository.swift:283,298,304             (clipDeleteBatch，被 5 处复用)
```

**形态不统一**：Harness 三处用 `BEGIN IMMEDIATE`，剪贴板两处用 `BEGIN`。

### 3.3 「一个业务动作跨多个仓储 → 多个事务」的具体点

| # | 业务动作 | 实际发生 | 证据 |
|---|---|---|---|
| **T1** | **删板**（`deleteBoard`） | 事务①删该板全部条目（`clipDeleteBatch` 自带 BEGIN/COMMIT）→ 事务②删板行（裸 `DELETE FROM clipboard_boards`，无事务）。**代码注释已承认**：「两步不共享事务」。中途 app 崩 → 板还在、条目全没。 | `ClipboardBoardRepository+SQLite.swift:130-160`（注释在 :135，条目删除在 :136，板行 DELETE 在 :147） |
| **T2** | **一轮超限清理**（`ClipboardLimitPruner.prune`） | 事务①`pruneClipboardItems`（按条数）→ 事务②`pruneClipboardItemsOverCapacity`（按容量，内部再调 `deleteClipboardItems` 又开一个事务）→ **事务③ 在库外**：`ClipboardImageGC.reclaim` 删磁盘图片文件。三次提交之间无原子性。 | `ClipboardLimitPruner.swift:49-52`；回收在 `ClipboardCapturePersist.swift:26` / `ClipboardImageGC.swift:76` |
| **T3** | **写入一条剪贴板**（采集落库） | 事务①`saveClipboardItem` upsert → 事务②`ClipboardImageGC.prune`（可能删别的记录）→ 库外写图片文件。 | `ClipboardCapturePersist.swift:16,26` |
| T4（轻度） | 多选删除 | 有 `ClipboardBatchDeleteRepository` 时 1 个事务；downcast 失败时退化为 N 个事务 | `ClipboardSelectionActions.swift:126-130` |

**T1 是唯一「同一业务动作内写了两个不同表、却不共享事务」的硬缺陷**，其余是「库 + 文件系统」的两阶段问题（后者在有 `ClipboardImageGC` 的孤儿清扫兜底，风险可控）。

> 补充：`clipDeleteBatch`(`DatabaseManager+ClipboardRepository.swift:283-304`)**本身就是个不错的事务原语**（先取被删行 → 删行 → 提交，失败回滚并返回 `nil`），
> 已经被 5 处复用。它差一步就能升级成通用事务 API —— 见 §6。

---

## 4. Schema 迁移：现在加一张表要改几个文件、几步？

### 4.1 现状：**两套并行的迁移机制**

| 轨 | 范围 | 版本号 | 位置 |
|---|---|---|---|
| 轨 A | `clipboard_items` / `clipboard_boards` | `PRAGMA user_version` 0→4（v5 是空占位） | `DatabaseManager+ClipboardSchema.swift`(v1,v2) + `ClipboardSchemaLadder.swift`(v3,v4,v5) |
| 轨 B | `harness_token_event` / `harness_session_scan` | **不用版本号**，靠 `CREATE TABLE IF NOT EXISTS` 每次重跑 | `Harness/HarnessUsageIndexStore.swift:10-12` 注释明说「PRAGMA user_version 由 DatabaseManager 管理，这里只 CREATE IF NOT EXISTS，避免与剪贴板迁移的版本判断互相干扰」 |

调度入口：`DatabaseManager.migrateIfNeeded()`（`DatabaseManager.swift:158-164`）**硬编码调用两个迁移函数**：

```swift
public func migrateIfNeeded() {
    migrateClipboardSchema()                    // 轨 A
    if let db { _ = harnessMigrateSchema(db) }  // 轨 B
}
```

→ **加第三个领域（比如 token 之外的第二张索引表）要改 `migrateIfNeeded()` 的硬编码列表**，没有登记表 / 注册机制。

### 4.2 「加一张表」的实际步数（轨 A，文档已写死在注释里）

`ClipboardSchemaLadder.swift:78-89` 的 v5 段注释给出加列的步骤；加**表**同理：

1. `ClipboardSchemaMapping.swift` —— 若新表要进 `clipboard_items` 的 SELECT，在 `Column` 追加 case（列名/列串/下标三处自动同步）
2. `ClipboardSchemaLadder.swift` —— 在当前非空段追加 `CREATE TABLE IF NOT EXISTS ...`（**不能在 v1–v4 里加**，注释 :84 明令）
3. `ClipboardSchemaMapping.swift:18` —— `latestVersion` +1
4. 新开下一个空段（把 `migrateClipboardToV5` 从占位改成实体，再开 v6）
5. `DatabaseManager+ClipboardSchema.swift:18-38` —— 版本阶梯里加一个 `if clipUserVersion(db) < N` 分支
6. 新建 `XxxRepository` 协议 + `DatabaseManager+XxxRepository.swift` 实现
7. 若是新能力：装配层加一处 `database as? any XxxRepository`（§1.2 A 类）
8. `TestRunner` 补列序 / 逐字段回读断言

**合计 6–8 个文件、7–8 步，其中 3 步是「记得别改错版本号」的纪律性工作。**

### 4.3 幂等性：**是幂等的，但靠的是人工纪律，不是机制**

- `CREATE TABLE IF NOT EXISTS`（`ClipboardSchemaLadder.swift`）+ ALTER 前用 `clipColumnExists`（`:96`）判列 → 重复执行无副作用 ✅；版本上限见 `ClipboardSchemaMapping.swift:18` 的 `latestVersion: Int32 = 4`
- 版本只在段尾 `clipAdvanceVersion` 推进(`:90`)，且注释明确警告「一段里别改别的版本号，否则 v3 永远重跑」（`DatabaseManager+ClipboardSchema.swift:9-16`）——**这个 bug 历史上真发生过**（注释里写「旧的一次性写法会让 v3 段每次启动把版本写回 2」）
- 轨 B 完全无版本号，纯靠 IF NOT EXISTS：加列能过（ALTER 需自己判存在），加**索引/约束变更/数据回填**会失效（每次都跑或每次都不跑）

---

## 5. 单一 owner：有「表 → 唯一写入方」映射吗？

**没有映射，也没有机制。** 现状是靠文件名聚合，而不是靠「表归属」。

### 5.1 写入方统计（`grep INSERT/UPDATE/DELETE FROM`，不含 TestRunner）

```
$ grep -rlE 'INSERT OR|INSERT INTO|UPDATE [a-z_]+ SET|DELETE FROM' --include='*.swift' . | grep -v /TestRunner/
./NetworkMonitorCore/ClipboardBatchDeleteStore.swift
./NetworkMonitorCore/ClipboardBoardRepository+SQLite.swift
./NetworkMonitorCore/ClipboardItemEditRepository.swift
./NetworkMonitorCore/ClipboardOCRStore.swift
./NetworkMonitorCore/DatabaseManager+ClipboardRepository.swift
./NetworkMonitorCore/Harness/HarnessUsageIndexAggregation.swift
./NetworkMonitorCore/Harness/HarnessUsageIndexPurge.swift
./NetworkMonitorCore/Harness/HarnessUsageIndexStore.swift
```

| 表 | 写入方（文件数） | 文件 | 单一 owner？ |
|---|---|---|---|
| **`clipboard_items`** | **7** | DatabaseManager+ClipboardRepository（增删改 ×4 语句）、ClipboardBoardRepository+SQLite（改 board_id / 删条目）、ClipboardItemEditRepository（删）、ClipboardOCRStore（改 ocr_text）、ClipboardBatchDeleteStore（删） | ❌ **7 个文件写同一张表** |
| `clipboard_boards` | 1 | ClipboardBoardRepository+SQLite | ✅ |
| `harness_token_event` | **3** | HarnessUsageIndexStore（插/删）、Aggregation（删）、Purge（删） | ❌ 3 个文件，但同族同目录（`Harness/`），风险低 |
| `harness_session_scan` | **3** | Store（插/删）、Aggregation（删）、Purge（删） | ❌ 同上 |

### 5.2 风险点

- `clipboard_items` 的 **7 个写入方里有 4 个会 DELETE**，而「删除必须返回被删行以便回收图片」这条不变量
  是靠「大家都记得调 `clipDeleteBatch`」维持的（`ClipboardBatchDeleteStore.swift:9-10`、`ClipboardCapacityPruneStore.swift:11-12`、
  `ClipboardImageGC.swift:63` 三处注释都在强调「共用同一个 GC 入口」）——**这是约定，不是约束**。
  新加一条删除路径忘了返回被删行 → 图片文件永久泄漏，无编译错误、无运行时报错。
- `ClipboardOCRStore.swift:19` 直接写 `UPDATE clipboard_items SET ocr_text`，绕开 `clipWriteItemText` 的哈希/预览重算路径。
  当前 OCR 不改正文所以安全，但它证明了「任何人都能对这张表写任意 UPDATE」。

---

## 6. 结论：目标形态两候选

### 6.1 候选 A（保守）：**保留 SQLite 直写 + 收口调用面**

把现有 6 个碎协议在装配层**提前拼成一个 `ClipboardStore` 外观**，删掉 4 处 `as?`；补一个 `Transaction` 原语；`query(sql:)` 从协议里下线。

- 改动面：`DatabaseService.swift`（协议）、`AppCoordinator+Clipboard.swift`（装配）、3 处 downcast、`clipDeleteBatch` 升级为 `withTransaction`、T1 删板改单事务。
- 影响文件：**约 8 个**，无 schema 变更，无迁移。
- 收益：消除全部静默退化；删板原子化；新增能力不再需要改协议。
- 代价：`DatabaseManager` 会更胖（协议收敛 = 实现类回到一处），**会撞同族门禁**——这条门禁必须先改口径，否则又要靠改名绕过（§2.2 的病灶重演）。

### 6.2 候选 B（激进）：**声明式 `TableStore` / 仓储基类**

引入三层：`TableSpec`（表名 + 列 + 索引 + 版本，声明式）→ `TableStore`（通用 CRUD + 事务 + 参数绑定，吃掉 23 处手写 `serialQueue.sync`）→ 领域仓储（只剩查询语义）。

- 改动面：新增 3–4 个基础设施文件；**现有 5 个剪贴板仓储实现全部重写**；迁移改成「`TableSpec` 数组按顺序执行，`user_version` 由框架推进」。
- 影响文件：**约 15–18 个**（含 TestRunner 的列序断言重写）。
- 收益：加一张表 = 声明一个 `TableSpec` + 写一个领域仓储，**文件数 8 → 2**；事务 / 绑定 / 迁移 / 幂等全部下沉到框架；owner 映射变成「`TableSpec` 登记的写入方」。
- 代价：一次性大改；SQLite 直写的好处（`clipDeleteBatch` 这类「先查后删」的精细操作）需要框架留 escape hatch，否则会被迫写更绕的代码。

### 6.3 对比与推荐

| | A 保守 | B 激进 |
|---|---|---|
| 影响文件 | ~8 | ~15–18 |
| 解决 downcast | ✅ | ✅ |
| 解决 T1 删板跨事务 | ✅ | ✅ |
| 解决「加表 8 步」 | ❌ | ✅ |
| 解决表 owner 漂移 | ❌ | ✅（部分） |
| 撞行数门禁 | **会** | 不会（新文件） |
| 可分批交付 | ✅ | ⚠️ 需要一次切换 |

**推荐：先 A 后 B，分 4 步走；A 的每一步都是 B 的前置。**

| 步 | 内容 | 影响文件 | 是否最难/收益最大 |
|---|---|---|---|
| **1** | `query(sql:)` 从 `DatabaseService` 协议下线（只留实现内部）；`_query` 的静默 `return` 改 `logger.error` | 2 | 便宜，先摘掉逃生通道 |
| **2** | 新增 `withTransaction(_:)`（把 `clipDeleteBatch` 的 BEGIN/COMMIT/ROLLBACK 抽出来，20 处手写事务收敛过去）；**T1 删板改成单事务** | 6 | ★ **最难但收益最大的一步**：要把 6 个文件 20 处手写事务改掉，还要保住 `clipDeleteBatch` 返回被删行的行为。做完之后「一个业务动作一个事务」才第一次成为可能 |
| **3** | 剪贴板 5 协议合成一个 `ClipboardStore` 外观（协议本身可保留做 SPI，但装配层只暴露外观）；删 4 处 `as?` | 8 | 收益大（消除全部静默退化），但要**先改行数门禁口径**，否则 `DatabaseManager` 族必然超基线 |
| **4** | 迁移登记表：`migrateIfNeeded()` 从硬编码 2 行改成遍历 `[SchemaMigration]`；轨 B 并入版本号 | 5 | 完成 B 的骨架，之后再加表才真的「只声明不实现」 |

> 若只做一步：做 **步 2**。它单独就能消掉唯一一个真正的数据一致性缺陷（T1），且是所有后续抽象的地基。
> 若只做一步且更在意「用户体感的功能开发速度」：做 **步 3**，但那要求 leader 先处理门禁口径问题。

### 6.4 对用户「是否通过统一数据库 / HTTP 接口访问」的直接回答

- **已经是统一数据库**：全项目单一 SQLite 文件 `~/Library/Application Support/macMonitor/monitor.db`，
  单一 `DatabaseManager` 实例、单一写队列、单一 `user_version`，**不存在第二套持久化**（`KeyValueStorage`/偏好与
  `SecretStorage`/凭据是另一条正当的旁路，不是数据库绕过）。
- **不建议为「统一」再引入 HTTP / 外部 DB**：本项目是单机菜单栏 App，SQLite 已经是零运维的最优解；
  引入 HTTP 层只会把进程内调用变成跨进程序列化，面板刷新路径（现为同步读）会立刻变慢。
- **真正的病不是协议不统一，是抽象停在了「谁都能拿裸指针」这一层**。达到「像组装组件一样只实现功能」，
  需要的是 §6.3 的 **步 2 + 步 3**（事务原语 + 装配期能力收敛），不是换存储。

---

## 7. 未覆盖项 / 交付边界

- 未构建、未跑测试（leader 独占构建），所有结论来自静态阅读与 grep；**行号以本次审计快照为准**。
- 未审计：`KeyValueStorage` / `SecretStorage` / 文件型存储（`ClipboardImageStore`、`CueSoundFileStore`、`KnownPeerStore`、`PairingStore`、`ScanTokenStore`）的架构完整度——它们是数据库之外的第二类持久化，本次按要求只做「数据持久化层的数据库部分」。
- 未核实：`harness_` 两表在轨 B 下若需加列（ALTER）的实际行为（当前无此变更，仅风险提示）。
- 未核实：`ClipboardRepository` 19 个调用方里是否有 TestRunner 之外的重复注入（未逐个读装配代码）。
- 写区声明：本文件是本次唯一写出的文件。
