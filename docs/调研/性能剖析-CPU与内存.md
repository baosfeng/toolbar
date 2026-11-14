# 性能剖析：CPU 与内存（实测）

> 采样对象：\`/Applications/NetworkMonitor.app\`（pid 74648，v1.21.1 (18)，2026-11-13 20:25 启动，已连续运行 15h24m）
> 采样时间：2026-11-14 11:50–11:59（面板**未展开**，无用户交互）
> 采样方式：\`sample\` 三份（10s / 30s / 10s）+ \`top -l 8 -s 1\` + \`footprint\` + \`vmmap -summary\` + \`heap\` + \`leaks\` + 统一日志
> 代码依据：知识图谱（codebase-memory）定位 + 源码核对。采样报出的 \`TransferController.swift:119\` / \`TransferPaneView.swift:161,195\` / \`PaneStateBandView.swift:39,53,67\` 与当前源码行号一致（这些文件 mtime 均早于部署包构建时间）。

> 待登记：本文需在 \`docs/索引.md\` 的「调研」段补一行引用（本轮由只读调研 agent 产出，未改索引）。

---

## 1. 结论（TL;DR）

| 指标 | 实测 | 证据 |
|---|---|---|
| CPU（生命周期均值） | **12.0%** | \`ps -Ao pid,pcpu,rss,etime\` → \`74648 12.0 1.1 191072 15:24:37\` |
| CPU（面板收起逐秒） | **0.0 / 3.1 / 4.6 / 4.9 / 5.0 / 6.9 / 8.8 / 4.8%** | \`top -l 8 -s 1\` |
| CPU（主线程，30s 采样） | **16.79%**（4073/24259 采样） | \`sample 74648 30\` 解析 |
| CPU（主线程，两份 10s 采样） | **10.2% / 13.4%** | 同上 |
| 内存 footprint | **204 MB**，峰值 **430 MB** | \`footprint\` → \`phys_footprint: 204 MB  peak: 430 MB\` |
| 堆分配 | 分配 **129.3 MB**，常驻 **62.5 MB**，**已换出 96.1 MB**，活跃分配 **1,401,941 个** | \`vmmap -summary\` MALLOC ZONE |
| 泄漏 | 454 处 / 21,360 字节（可忽略） | \`leaks 74648\` |

**一句话根因**：局域网互传控制器一个 **1 秒重复 Timer** 每秒无条件重建页脚状态带（5 个条目 × 3 个视图 = 15 个新视图/秒），每次重建让 \`NSStackView\` 的第一基线约束重新入引擎，于是下一个显示周期要跑一遍全树 Auto Layout，而每个 \`NSTextField\` 的基线求解都要查 AppKit 的文本测量缓存——缓存键比较是**逐字符比较属性串**（\`CFEqual\` → \`__CF_IS_OBJC\`），把主线程烧掉一半以上的忙碌时间。

**修复该一条链路**：预计 CPU 12% → 1–2%（见 §8 P0），同时止住 48B/64B 小对象的持续累积（内存增长同源）。

---

## 2. 实测数据

### 2.1 进程与内存

\`\`\`
$ ps -Ao pid,pcpu,pmem,rss,etime,comm | grep NetworkMonitor
74648  12.0  1.1 191072    15:24:37  /Applications/NetworkMonitor.app/Contents/MacOS/NetworkMonitor
# ↑ 历史读数（当时的包名与可执行名都还是英文）。现在同一命令应看到
#   /Applications/一览.app/Contents/MacOS/一览：包名与包内可执行名都已中文化，数值口径不变。

$ footprint 74648 | tail -6
 204 MB      34 MB       336 KB      9697    TOTAL
    phys_footprint: 204 MB
    phys_footprint_peak: 430 MB

$ vmmap -summary 74648 | tail -14
DefaultMallocZone_0x103ca8000   225.6M  62.5M  62.5M  92.2M  1319936  125.3M  29.4M  20%
TOTAL                           233.7M  64.8M  64.8M  96.1M  1401941  129.3M  31.6M  20%

$ heap 74648 | head -18
Physical footprint: 204.1M   (peak 430.2M)
All zones: 1407326 nodes malloced - ... 64[128410] ... 80[69130] ... 96[31173] 112[35377] 128[30076] 160[26421] 192[5657] 224[3611] 256[3005] 320[5914] 512[10998] 48[461415]

$ leaks 74648 | head -1
Process 74648: 454 leaks for 21360 total leaked bytes.
\`\`\`

- 活跃分配 140 万，其中 **48 字节对象 461,415 个**、64 字节 128,410 个、80 字节 69,130 个 —— 典型「海量小对象」形态（平均 92 字节/分配），与「每秒重建视图 + 每秒新建属性串」同源。
- 96.1 MB 已被系统换出：说明历史峰值（430 MB）远超当前常驻，内存压力确实发生过。
- \`leaks\` 结论：无实质泄漏（21 KB），内存问题不是「漏」而是「持续新建」。

### 2.2 CPU 归属（三份 sample 互相印证）

| 线程 / 队列 | 10s 采样 | 30s 采样 | 说明 |
|---|---|---|---|
| Main Thread | 10.2% | 16.79% | 绝对大头（占全部忙碌时间的 90%+） |
| \`com.networkmonitor.system-metrics\`（串行） | 0.47% | 0.40% | 系统指标采样帧 |
| \`com.networkmonitor.process-poll\`（串行） | 0.29% | 0.65% | nettop fork + 解析 |
| 其余（CA DispatchGroup、网络、CA::CG 等） | <0.2% | <0.2% | 可忽略 |

> 主线程忙碌采样按 1.237ms/样本（30s / 24259 样本）折算；主线程占全部 CPU 的 16.79%，与 \`ps\` 生命周期均值 12%、\`top\` 逐秒 3–9% 的量级一致（逐秒值受采样窗口与突发影响）。

---

## 3. Top 5 热点（30s 窗口；括号内为三份采样取值范围）

按「自身时间」聚合（leaf 减去子树，排除 mach_msg / workq 等空闲陷阱）：

| # | 热点 | 占比（30s / 两份 10s） | 调用链要点 |
|---|---|---|---|
| 1 | **文本测量缓存键比较**（\`NSCache\` → \`CFEqual\` → \`__CF_IS_OBJC\`） | **13.29%** / 10.44%、13.3% | \`NSStackView firstBaselineOffsetFromTop\` → \`NSTextField._baselineOffsets\` → \`NSCell cellSize\` → \`NSTextFieldCell cellSizeForBounds:\` → \`NSCellRectForString\` → \`NSCache objectForKey:\` → \`_entry_get_optionally_checking_collisions\` → \`__NSCacheKeyEqual\` → \`CFEqual\` → \`__CF_IS_OBJC\`（单点最大 1213 采样 = 5.00%） |
| 2 | Auto Layout 约束求解 | 1.05% / 0.96%、2.99%* | \`-[NSWindow updateConstraintsIfNeeded]\` → \`-[NSView updateConstraintsForSubtreeIfNeeded]\` → \`_updateConstraintsForSubtreeIfNeededCollectingViewsWithInvalidBaselines:\`（10s 样本中该函数自身 227 采样 = 2.99%） |
| 3 | 显示周期 / 事务提交 | 1.03% / 0.88% | \`UC::DriverCore::continueProcessing\` → \`stepTransactionFlush\` → \`CA::Transaction::commit\` → \`NSDisplayCycleFlush\` → \`NSDisplayCycleObserverInvoke\` |
| 4 | 图层树构建 | 0.64% / 0.57% | \`-[NSView _buildLayerTreeWithOwnLayerRequirement:someAncestorWantsLayer:singleLayerOut:layerArrayOut:]\` |
| 5 | 应用侧触发源：状态带每秒重建 | 每秒 1 次（10s 采样中 21 采样命中 \`TransferController.render()\` 路径） | \`TransferController.start()\`（1s Timer）→ \`render()\` → \`TransferPaneView.update(...)\` → \`updateBand\` → \`PaneStateBandView.update(items:)\` → \`clearContent()\` + \`makeItemView\` |

\* 热点 2 在 30s 窗口被热点 1 覆盖（同一批栈更深处先命中测量缓存分组），10s 窗口单独统计时为 2.99%。

> 关键结构：**热点 1/2/3/4 是同一次失效的四个阶段**——热点 5 每秒制造一次视图重建 → 约束失效 → 显示周期跑全树布局（2）→ 文本测量（1）→ 提交事务、重建图层树（3、4）。因此修 5 等于同时消掉 1–4 的主体。

---

## 4. 根因链（逐跳证据）

| 跳 | 代码位置 | 事实 |
|---|---|---|
| 1 | \`Sources/NetworkMonitor/Transfer/TransferController.swift:115-121\` | \`Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true)\`，闭包里 \`pollPendingOffers()\` **和 \`render()\`**；无面板可见性判断、无内容变化判断 |
| 2 | \`Sources/NetworkMonitor/Transfer/TransferController.swift:168-177\` | \`render()\` 无条件调 \`panel?.update(devices:sessions:selectedDeviceId:statusText:autoAcceptText:autoAcceptActive:)\` |
| 3 | \`Sources/NetworkMonitor/Transfer/TransferPaneView.swift:161-162\` | \`update(...)\` 每次都调 \`updateBand(...)\` |
| 4 | \`Sources/NetworkMonitor/Transfer/TransferPaneView.swift:192-202\` | \`updateBand\` 每次都构造 5 项数组并调 \`stateBand.update(items:)\`，**没有** 类似 \`deviceSignature\`/\`sessionSignature\` 的变更判定 |
| 5 | \`Sources/NetworkMonitor/MenuPanel/PaneStateBandView.swift:38-49\` + \`:64-69\` | \`update(items:)\` 先 \`clearContent()\`（遍历 \`arrangedSubviews\` 逐个 \`removeArrangedSubview\` + \`removeFromSuperview\`），再 \`contentStack.addArrangedSubview\` 新建条目 |
| 6 | \`Sources/NetworkMonitor/MenuPanel/PaneChromeViews.swift:125-135\` | \`makeItemView\` 每次新建 2 个 \`NSTextField\` + 1 个 \`NSStackView(orientation: .horizontal, alignment: .firstBaseline)\` → 每次调用 = 3 个视图 × 5 项 = **15 个视图/秒** |
| 7 | 采样调用链（30s 样本） | \`NSStackView updateConstraints\` → \`_updateDeclaredConstraints\` → \`_tryToAddConstraint\` → \`_layoutEngine_didAddLayoutConstraint\` → \`_lowerIntoExpression\` → \`nsli_lowerAttribute:intoExpression:withCoefficient:\` → \`NSStackView firstBaselineOffsetFromTop\` → \`NSTextField _baselineOffsets\` → \`NSCell cellSize\` → \`cellSizeForBounds:\` → \`NSCellRectForString\` → \`NSCache objectForKey:\` → \`CFEqual\`（13.29%） |

**旁证（同一文件内的正确做法）**：\`TransferPaneView.swift:164-184\` 对设备行、任务行都做了签名比较（\`devicePad != deviceSignature\` / \`sessionIdPad != sessionSignature\`）才重建，唯独页脚状态带没有——这是「漏掉一处 diff 判定」而非设计选择。

**为什么面板收起也在烧 CPU**：\`TransferController.start()\` 由组合根 \`AppCoordinator.start()\` 无条件调用（\`Sources/NetworkMonitor/AppCoordinator.swift:107\` → \`AppCoordinator+Transfer.swift:14\`），与面板是否展开无关；\`MenuPanelController.tick()\` 虽然有 \`guard popover.isShown\`（\`MenuPanelController+Open.swift:87\`），但 \`TransferController\` 的 1s 定时器根本不走 tick()。实测确认面板是收起的：\`CGWindowList\` 里 7 个窗口全部 \`onscreen=false\`（面板 346×414 在 (949,28)），\`System Events\` 窗口数 0。

---

## 5. 次要热点（真实现象，量级小）

| 现象 | 证据 | 量级 | 位置 |
|---|---|---|---|
| nettop 每 3 秒 fork 一次子进程 | \`NetworkMonitor.swift:87\` \`pollInterval = 3.0\`；\`Core.swift:168-188\` \`Process()\` + \`waitUntilExit()\`（每次生命周期约 1 秒） | process-poll 队列 0.29–0.65% CPU；\`runNettopSnapshot()\` 包含式 24ms/10s | \`Sources/NetworkMonitor/NetworkMonitor.swift:91-142\`、\`Sources/NetworkMonitorCore/Core.swift:168-188\` |
| 系统指标 1 秒采样 | \`SystemMonitorPreferences.swift:30\` \`defaultSampleInterval = 1.0\`；\`SystemMonitor.swift:71-82\` 重复 Timer，每帧后台跑 CPU/内存/磁盘/GPU/温度 5 个采样器，5 秒一次慢节拍 | system-metrics 队列 0.40–0.47% CPU | \`Sources/NetworkMonitor/SystemMetrics/SystemMonitor.swift:92-200\` |
| powerd XPC 连接反复建/断 | 统一日志 5 分钟内 \`com.apple.iokit.powerdxpc\` activating/invalidated **48 次**（≈6.25s 一次） | 连接建立开销 + 能耗，CPU 计入上行 | \`SystemMonitor+SlowMetrics.swift\` 的 \`powerReader\` |
| 局域网发现 UDP 广播持续失败 | 统一日志 90 分钟内 \`UDP 发送失败 host=239.255.77.77 errno=65\` **599 次**（≈9s 一次） | 每次失败发送 + 一条日志；发现层常驻 | \`Sources/NetworkMonitorCore/Transfer/Discovery/UdpDiscoveryService.swift\` |
| 额度刷新不受面板可见性影响 | \`MenuPanelController+Open.swift:84-86\`：tick() 第一句就是 \`billingMonitor?.refresh()\`（内部 60s 节流 + 429 退避） | 可接受，但与「面板收起应静默」的原则不一致 | 同上 |
| 剪贴板轮询 | \`PasteboardWatcher.swift:100-117\`：一次性 Timer 按 0.5/2/5s 档重排，每 tick 只读 \`changeCount\` | **不是热点**（采样中无相关栈） | \`Clipboard/PasteboardWatcher.swift\` |
| 图表重绘 | 网络折线 \`maxHistory = 60\`、系统历史按序列压缩、面板刷新 5s 节流（\`MenuPanelController.swift:88-90\`） | 未见热点 | \`MenuPanel/*\` |

---

## 6. 内存与文件交换建议

### 6.1 现状判断

- **不是泄漏**（\`leaks\` 21 KB）。问题是「持续新建小对象」：46 万个 48B、12.8 万个 64B、6.9 万个 80B。
- 峰值 430 MB / 当前 204 MB / 换出 96 MB：**说明用户已实际吃到内存压力**（页被换出，机器整体变卡）。
- AppKit 的隐式缓存（\`NSStringMeasurementCache\`、字体/图层缓存）会随「每秒 15 个新视图 + 属性串」缓慢增长，且无上限可调。

### 6.2 建议的落盘与上限

| 数据 | 建议 | 理由 |
|---|---|---|
| 剪贴板图片原图 | 保持现状（已落盘 \`ClipboardImageStore\`），内存只留缩略图；给缩略图缓存加显式上限（建议 200 张 / 32 MB，LRU 淘汰） | 图片是唯一可能 MB 级的对象，必须落盘 + 有上限 |
| 剪贴板文本条目 | 面板只加载可见页（如最近 200 条），滚动分页查 SQLite；全文浮层按需读 \`ClipboardRepository\` | 避免一次性把全历史读进内存 |
| Token 索引 | 内存只保留**聚合结果**（今日/7d/30d 的日桶 + 项目/模型维度），原始事件流继续以 zstd 文件增量读、不常驻 | 索引体积随会话数线性增长，是最该「按需 + 落盘」的一项 |
| 趋势 / 直方图序列 | 保持现有上限（网络 60 点、系统历史压缩），二级详情页数据按需查询，不预分配 | 现状已合理 |
| AppKit 文本测量 | 状态带这类固定 key（文本+字号）建议自建小型测量缓存并设上限，避免回落到 \`NSCache\` 的 O(n) 键比较 | 缓解热点 1 的常数因子（次要手段） |
| 通用 | 面板收起时停止一切视图重建（见 §8 P0），是内存与 CPU 的同一把钥匙 | 每秒 15 视图 × 15h ≈ 81 万次视图创建，与 140 万活跃分配同源 |

---

## 7. 优化方案（按收益排序）

### P0 状态带每秒重建（收益最大，风险最低）

- **改什么**
  1. \`TransferController.render()\` 开头加内容签名早退：\`"\(devices.count)|\(sessions.count)|\(activeCount)|\(autoAcceptText)|\(statusText)"\` 与上次相同直接 \`return\`（照抄同文件 \`deviceSignature\` 的写法）。
  2. \`TransferController\` 的 1s Timer 只做 \`pollPendingOffers()\` 与模型更新；面板不可见时不向视图推数据（\`panel?.update\` 内部加 \`guard isShown\`，或调用处判断）。
  3. \`PaneStateBandView.update(items:)\` 增加 item 快照比较，内容相同不 \`clearContent()\`。
  4. 中期：状态带改为「预建固定条目视图 + 只改 \`stringValue\`」，彻底不碰 \`addArrangedSubview/removeArrangedSubview\`。
- **预计**：主线程 13–17% → 1–2%；\`ps\` 生命周期均值 12% → <1.5%；48B 小对象不再线性累积。
- **风险**：低。语义不变，只去掉冗余重建。注意签名要覆盖每个 item 的 key+value（避免「数值变了但签名相同」的漏刷）。
- **验收**：同款 \`sample\` 复跑，热点 1 应降到 <0.5%，\`PaneStateBandView\` 不再出现在采样热点；\`footprint\` 24h 后 48B 对象数不再增长。

### P1 nettop 采样降频 / 长驻

- **改什么**：面板收起时把 \`pollInterval\` 从 3s 放宽到 10–15s（或仅面板展开时采样）；中期改为长驻 \`nettop -x -l 0\` 流式增量解析，避免每 3 秒 fork/exec。
- **预计**：0.3–0.65% → <0.1%，并减少子进程抖动与能耗。
- **风险**：中（流式解析要处理增量输出与断行）；建议先做「收起降频」这一半。

### P2 系统采样节拍 + power XPC

- **改什么**：面板收起时 \`systemSampleInterval\` 由 1s → 5s；\`powerReader\` 的 powerd XPC 改为长连接，或把读数间隔放宽到 15–30s。
- **预计**：合计 <0.2% CPU，并消除每 6 秒一次的 XPC 建连（日志 48 次/5 分钟）。
- **风险**：低（注意状态栏告警阈值仍要够灵敏：可在「有告警阈值启用」时保持 1s）。

### P3 局域网发现退避

- **改什么**：UDP 广播 \`errno == 65\`（无路由）时指数退避到 30–60s；无配对/无传输进行时暂停广播，打开互传面板时立即刷新一次。
- **预计**：消除 599 次/90 分钟的失败发送与日志。
- **风险**：低（发现延迟变大，可用面板打开时主动刷抵消）。

### P4 文本测量常数因子（可选）

- **改什么**：状态带条目由 \`alignment = .firstBaseline\` 改为 \`centerY\` 对齐（或给 value label 固定行高），减少 \`cellSizeForBounds\` 调用；配合自建测量缓存。
- **预计**：在 P0 之后再降 0.2–0.5%，仅在 P0 无法完全落地时才有意义。
- **风险**：低，但会改变 1–2pt 的垂直基线观感，需要视觉复核。

---

## 8. 复跑命令

\`\`\`bash
PID=$(pgrep -f "/Contents/MacOS/一览( |$)" | head -1)   # 旧包（可执行名 NetworkMonitor）用 /Contents/MacOS/NetworkMonitor
ps -Ao pid,pcpu,pmem,rss,etime,comm | grep -E "MacOS/一览" | grep -v grep
top -l 8 -s 1 -stats pid,cpu,mem,command | grep -E "^ *$PID"
sample "$PID" 30 -file /tmp/nm.sample        # 热点表在文件末尾「Sort by top of stack」
footprint "$PID" | tail -6                    # footprint 与峰值
vmmap -summary "$PID" | tail -14              # MALLOC ZONE：allocated / resident / swapped
heap "$PID" | head -18                        # 尺寸直方图（48B/64B 小对象计数）
leaks "$PID" | head -1
log show --last 5m --style compact --predicate 'process == "NetworkMonitor"' | grep -c powerdxpc
log show --last 90m --style compact --predicate 'process == "NetworkMonitor"' | grep -c 'UDP 发送失败'
swift /tmp/winlist.swift                      # CGWindowList：确认面板是否 onscreen（见下）
\`\`\`

窗口核验脚本（用来确认「面板收起」这一前提）：

\`\`\`swift
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list where ((w[kCGWindowOwnerName as String] as? String) ?? "").contains("NetworkMonitor") {
    print(w[kCGWindowNumber as String] ?? "-", w[kCGWindowIsOnscreen as String] ?? "-", w[kCGWindowBounds as String] ?? "-")
}
\`\`\`

---

## 9. 附注

- 部署包版本 **1.21.1 (18)**，而 \`AGENTS.md\` 标注源码已到 **1.23.0** —— 本次实测对象落后于当前源码。热点链所在的 \`Transfer/\`、\`MenuPanel/Pane*.swift\` 自 2026-11-12 起未改动，故代码结论对当前源码同样成立；但**修完 P0 后需重新打包部署**才能验证收益。
- \`MenuBarManager.swift\` 的采样行号（:312 call \`update()\`）与当前源码（\`:280-324\`）不一致，属打包时该文件版本差异；本报告所有行号一律以当前源码为准。
- 采样期间 \`codebase-memory\`、\`swift-frontend\` 等进程占用较高，会压缩 sample 的时间片；三份独立采样在「测量缓存」一项上的占比（10.4% / 13.3% / 13.29%）一致，结论不受干扰。
