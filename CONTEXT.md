# 项目上下文（共享语言）

NetworkMonitor / macMonitor — macOS 菜单栏应用。本文档定义项目术语，帮助 agent 用 1 个词代替 20 个词。术语更新时同步维护本文件。

## 核心术语

| 术语 | 定义 | 避免的说法 |
|------|------|-----------|
| **组合根** | `AppCoordinator`，唯一允许创建具体实现类的地方 | 依赖容器、工厂 |
| **仓储（Repository）** | 按领域拆分的数据库接口：`ClipboardRepository` | 数据访问层 |
| **AppDatabase** | `DatabaseService & ClipboardRepository` 组合 typealias，UI 注入用 | 数据库对象 |
| **分层刷新** | 菜单栏更新频率分层：网速 1s / 流量 5s | 定时器策略 |
| **计费 provider** | 实现 `BillingProvider` 协议的云服务商额度源（Ollama / Open Design），注册后自动出现在额度页 provider 选择器 | 计费插件、余额接口 |
| **编码计划窗口** | Open Design 按 credits 计量的滚动额度窗口（5 小时 / 每周），映射为 `BillingPercentLimit` | 套餐、配额 |
| **用量聚合** | Open Design `/billing/usage` 顶层 `summary` + `totalCount` 为全范围汇总（与分页 `limit` 无关） | 明细列表 |
| **Token 用量** | DSH 会话事件流中 `assistant/message` 的 `usage` 聚合（未缓存输入 / 输出 / 缓存读），按 Asia/Shanghai 分桶 | token 统计、消耗量 |
| **会话去重** | 同一会话目录的 v0/v3/v4 多版本文件按内容键（time + model + 四项计数）合并；`seq` 跨版本会重启，不可作键 | 去重、合并 |
| **系统指标快照** | `SystemMetricsSnapshot`（timestamp + cpu/gpu/memory/disk/thermal/load/processes/battery 全可选）：某项不可得就 nil，UI 显示「—」，不隐藏整卡 | 状态对象、监控数据 |
| **首帧基线** | 差分类指标（CPU 利用率、磁盘读写速率 / IOPS / 繁忙度、进程 CPU%、GPU 功耗）首帧只建基线、返回 nil 而非 0，第二次起才有值 | 预热、初始化 |
| **P/E 核顺序** | 每核利用率下标 **E 核在前、P 核在后**（实测 `ioreg cluster-type`），分组一律走 `splitCores` | 大小核、异构核 |
| **sqrt 绝对刻度** | 进程 CPU 榜条形长度 `min(1, sqrt(cpuPercent) × 13 / 100)`，满条 = 100% = 占满一个核。**不是榜首归一化**：榜首跳变会让所有条联动缩放（实测同一条 15.77% 的进度在 26.2–197.1pt 间摆动，波动 170.8pt；绝对刻度下恒 51.6pt，波动 0） | 相对刻度、按最大值归一化 |
| **首屏预算** | `maxHeight = 520pt` 下的信息优先级分配。v6 版2 把四处信息下沉到二级详情页（每核柱阵 / 显存条 / 内存四段数值 / 磁盘读写曲线），目标是四联 + 五卡 + 状态带一屏看全；实测以快照为准 | 一屏显示、压缩排版 |
| **估算功耗** | 状态带「估功耗」= IOReport `Energy Model` 的 `GPU Energy` 累加器差分（单位 nJ），是估算不是功耗计读数；CPU 功耗恒 0 无法合成整机功耗 | 功耗、整机功率 |

## 关键事实（易错点）

- 数据库金额一律 **CNY**（USD 在写入前经 `CurrencyConfig` 转换）
- 剪贴板数据落库后发 `AppEvents.postClipboardChanged()`，UI 订阅后立即刷新
- `NetworkMonitorCore` 禁止 import AppKit；依赖方向 App → Core
- 测试：`swift run --disable-sandbox --build-system native TestRunner`，内存 SQLite，无 XCTest
- Open Design 额度接口只认浏览器 Cookie（`__Secure-better-auth.session_token`），Bearer 一律 401；用量接口只接受最近 7 天窗口（超窗或终点在未来都 400 `invalid_workspace_usage_time_range`），**汇总必须读顶层 `summary` / `totalCount`，不要翻页**
- 系统监控：CPU 功耗恒为 0（不可得）、风扇转速在 Apple Silicon 不可得，UI 用「—」表达，**不填假值**；恒不可得项还有 CPU 频率绝对值、GPU 独立温度、电池健康度百分比、Wi-Fi SSID/BSSID，一律不出该项、不留空位
- **Wi-Fi 链路的 nil 不是 0**：CoreWLAN 在 Wi-Fi 关闭 / 未连接 / 无接口时返回 0 等占位值，采样器一律折成 `nil`，两处 UI 都不许显示「0 dBm」或「极佳」；`ssid()` / `bssid()` 需定位授权，不申请、不调用
- **P 核 P-state 与本机无关**：IOReport `CPU Stats` 的 residency 是 **mach ticks**（与进程 CPU% 同一个时基坑），且同名通道会重复出现、**必须按数组下标读**；更关键的是本机 P 核稳态只有 IDLE / 满性能两态，非 IDLE 占比约等于 CPU 利用率，故**已判定不接入**，不要按「16 态聚合 4 档」的老结论重开
- 磁盘速率必须按 `IORegistryEntryGetRegistryEntryID` 配对（按数组索引会串号出负速率）；内存页大小用 `host_page_size()` 动态取（Apple Silicon 16KiB / Intel 4KiB）
- **进程 CPU% 的时基是 mach ticks 不是纳秒**：`proc_pidinfo(PROC_PIDTASKINFO)` 的 `pti_total_user/system` 单位是 tick，Apple Silicon `mach_timebase_info = 125/3`（1 tick ≈ 41.67 ns）。按纳秒直接换算会**系统性偏小 41.67 倍**（3 线程自旋实测误算 7.2% vs 正确 298.0%）。nsPerTick 必须运行时读取，禁止硬编码（Intel 是 1/1）。详见 [进程 CPU 百分比时基换算](docs/踩坑/运行时/进程CPU百分比时基换算.md)
- **IOReport 单位混排**：`Energy Model` 组同一批通道里混着 uJ / nJ / mJ；有值的 `GPU Energy` 是 **nJ**，恒为 0 的 `CPU Energy` 标的是 mJ。单位一律读通道自带 label 换算，**禁止硬编码量纲**（否则出「0.29 kW」这种荒谬读数）
