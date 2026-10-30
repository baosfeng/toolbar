# 系统监控（CPU / GPU / 内存 / 磁盘 / 温度）· 可行性调研

> 目的：判断菜单栏应用能否**只读、免 root** 地常驻采样 CPU / GPU / 内存 / 磁盘 / 温度 / 功耗，并给出每项的首选 API 与降级路径。调研时间 2026-10。
>
> 实测环境：macOS 27.0.1 (26A434) · Apple M1 Pro（10 核 8P+2E）· 16 GB · 页大小 16384 · 磁盘 926 GB · swiftc 6.4（仅 CommandLineTools，无完整 Xcode SDK）。证据全部来自 `/tmp/sysmon-probe` 下的最小 Swift 探针 `probe_*.swift`；`/tmp` 会清空，故结论与源码行号固化在本文。

## 一、目标与范围

一句话：为 NetworkMonitor 增加「系统监控」，只读、无 root、1 s 级刷新；**拿不到的指标不出现在 UI，而不是显示假值**。

| 指标 | 是否可做 | 首选 API | 需权限 | 备注 |
|---|---|---|---|---|
| CPU 总利用率 | ✅ | `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` 差分 | 无 | 单次采样 0.007 ms |
| CPU 每核利用率 | ✅ | 同上，按 `cpuIndex*CPU_STATE_MAX + {user,system,idle,nice}` | 无 | 本机 10 核 |
| 内存 | ✅ | `host_statistics64(HOST_VM_INFO64)` + `host_page_size()` | 无 | 1 ms 级 |
| 内存压力 / swap | ✅ | `sysctl kern.memorystatus_vm_pressure_level`、`vm.swapusage` | 无 | 压力轮询别用 DispatchSource |
| 磁盘容量 | ✅ | `getmntinfo(MNT_NOWAIT)` | 无 | 0.008 ms |
| 磁盘读写速率 | ✅ | `IOBlockStorageDriver` → `Statistics` 差分 | 无 | 必须按 RegistryEntryID 配对 |
| GPU 利用率 | ✅ | `IOAccelerator` → `PerformanceStatistics` | 无 | 首帧 0%，需预热丢弃 |
| SoC 温度 | ✅（私有 API） | `IOHIDEventSystemClient` | 无 entitlement | ≈0.95 ms/传感器 |
| GPU 功耗 | ✅（估算） | `IOReport` 「Energy Model」→ `GPU Energy` | 无 | ≈3.2 W（按 nJ 换算） |
| CPU 功耗 | ❌ | `IOReport` 「Energy Model」→ `CPU Energy` | — | 实测恒 0，UI 不出该项 |
| 风扇转速 | ❌ 本轮未取得 | — | — | SMC 无键路径，IOHID 未暴露 |
| CPU 频率 | ⏳ 待补 | `IOReport` 「CPU Stats」每核 state 驻留 | 无 | 组存在（22 channels），未取到可用数值 |

## 二、方案对比

### 2.1 CPU：`host_processor_info` vs `host_statistics`

| 方案 | 粒度 | 取舍 |
|---|---|---|
| `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` | 每核 4 态 ticks | **采用**：一次调用同时得到每核与总量（每核求和即总量），省一次系统调用 |
| `host_statistics(HOST_CPU_LOAD_INFO)` | 仅总量 4 态 | 仅作对账：`probe_cpu` 会打印两路口径差值（`diff between A(per-cpu sum) and B(host_statistics)`），实现期用它校验求和口径 |

结论：主路径 `host_processor_info`，`host_statistics` 只用于开发期对账、不进运行时；两者均为公开头文件 API，免权限。

### 2.2 GPU：`IOAccelerator` vs `IOReport` GPUPH vs Metal HUD

| 方案 | 输出语义 | 实测 | 结论 |
|---|---|---|---|
| `IOAccelerator` → `PerformanceStatistics` | 直接给 `Device / Renderer / Tiler Utilization %` | 空闲 0%，Metal compute 压满 94–100%，≈0.041 ms/次 | **首选** |
| `IOReport` 「GPU Stats」（`GPUPH`/`BSTGPUPH`/`PWRCTRL`） | 性能态**驻留占比**（`OFF=9.6% P1=50.6% …`），不是利用率；`GPU Active Time` 读到 `Int64.min`（无效） | 能读但语义不对，需自建「驻留 → 利用率」映射 | 备选：仅当 `Utilization %` 键缺失时降级 |
| Metal HUD | 开发者叠层，靠环境变量 / `MTLCaptureManager` 开启 | 进程内无法稳定取数，且改变观感 | 不采用 |

结论：GPU 走 `IOAccelerator`；`GPUPH` 必须先自证映射误差才可上 UI。

### 2.3 温度：SMC vs IOHID vs powermetrics

| 方案 | 实测结果 | 结论 |
|---|---|---|
| AppleSMC 直读 | `IOServiceMatching("AppleSMC")` 只匹配到 `AppleSMCKeysEndpoint`；`IOServiceOpen` 免 root 成功，但旧 smc.c 协议 `selector=2` 返回 `0xe00002c2` = `kIOReturnBadArgument`（**不是** `kIOReturnNotPrivileged`） | 不可用：macOS 27 协议已变，且非权限问题 |
| `IOHIDEventSystemClient`（私有） | 64 个 PMU 类传感器，`PMU tdie2 51.78 °C`；复用 client 后读 2 个 1.975 ms、读 64 个 64.2 ms | **采用**，但只读 2–4 个关键传感器 |
| `powermetrics` | `powermetrics -n 1 -i 200` → `powermetrics must be invoked as the superuser`（exit 1）；`sudo -n true` 要密码 | 不可用：不提权、不杀进程、不做常驻特权进程 |

## 三、实测证据

在 `/tmp/sysmon-probe` 内编译运行（`iodeport.log`、`pm.log` 为留存原始日志，其余为对应探针打印字段的实测值）：

```bash
cd /tmp/sysmon-probe
swiftc -O probe_cpu.swift -o probe_cpu && ./probe_cpu
swiftc -O probe_mem.swift -o probe_mem && ./probe_mem
swiftc -O probe_disk2.swift -o probe_disk2 -framework IOKit && ./probe_disk2
swiftc -O probe_gpu3.swift -o probe_gpu3 -framework IOKit -framework Metal && ./probe_gpu3
swiftc -O probe_cost2.swift -o probe_cost2 -framework IOKit && ./probe_cost2
swiftc -O probe_cost3.swift -o probe_cost3 -framework IOKit && ./probe_cost3
swiftc -O probe_ioreport2.swift -o probe_ioreport2 -framework IOKit && ./probe_ioreport2
```

| 证据 | 关键输出行 | 出处 |
|---|---|---|
| CPU 每核 + 开销 | `cores: 10` · `core00 … core09` 各一百分比 · `PER-CORE aggregate: xx.x%` · `single sample cost … 0.007 ms` | `probe_cpu.swift:49,64,66,81` |
| 内存 / 页大小 | `kr=KERN_SUCCESS  host_page_size=16384 bytes (16KiB = Apple Silicon)` · `USED (total-free-speculative) = …` · `host_statistics64 cost: 0.0010 ms` | `probe_mem.swift:35,66,88` |
| 磁盘多实例 | `instances: N   (key = IORegistryEntryID，必须用它配对，数组索引会串号)` · `id=… read x.xx MB/s  write y.yy MB/s` | `probe_disk2.swift:35,41` |
| GPU 利用率 | `idle#1..3: Device=0% Renderer=0%` → `busy (cmd#N): Device=94~100%` → 停止负载后回落 0 | `probe_gpu3.swift:25,59,68` |
| GPU 首读现象 | `read#1 (冷/刚被读)` / `read#2 (立即再读)` 连续两次对比 | `probe_cost3.swift:50-54` |
| 温度 | `PMU 类传感器: 64 个` · `只读 PMU 64 个 64.2 ms` / `2 个 1.975 ms` · `PMU tdie2 51.78 °C` | `probe_cost2.swift:41,60,76` |
| 功耗 | `GPU Energy delta=3243185370   (as nJ => 3.243 W …)`，同轮 `CPU Energy delta=0` | `iodeport.log:206` · `probe_ioreport2.swift:80` |
| GPU 态驻留（对照） | `GPUPH: OFF=9.6% P1=50.6% P2=8.1% P3=5.7% P4=6.9% P5=6.8% P6=12.2%` · `PWRCTRL: IDLE_OFF=9.6% PERF=73.4% DEADLINE=12.1% PRFBOOST=4.9%` | `iodeport.log:380,472` |
| SMC 错误码 | `sel=2 kr=0xe00002c2 …` | `probe_smc2.swift:34` |
| powermetrics | `powermetrics must be invoked as the superuser` | `pm.log` |

## 四、已知陷阱与降级策略

| 陷阱 | 现象 | 处置 |
|---|---|---|
| 磁盘串号 | 按数组索引/名字配对两次快照，读写速率出现 **-339133 MB/s** 负值 | 一律以 `IORegistryEntryGetRegistryEntryID` 作 key 配对；缺基线就跳过该实例（`probe_disk2.swift:35-37`） |
| GPU 首读 0% | 冷读 `PerformanceStatistics` 得 0%，紧接的 Metal 负载也读到 0，隔 1 s 才正常 | 采样器启动即预热一次并丢弃；`Device Utilization %` 取不到 ⇒ 回退 `Renderer Utilization %`，仍 nil 则隐藏 GPU 块 |
| 温度开销线性 | 64 个传感器 64.2 ms，1 s 周期吃掉 6.6% CPU | 只读 2–4 个 PMU 传感器（<3 ms）；若确需全量，降到 5 s 一次（均摊 <1.5%） |
| 页大小硬编码 | 按 4096 算内存会偏小 4 倍 | 每次启动 `host_page_size()` 动态取，本机 16384 |
| 私有 API 失效 | `IOHIDEventSystemClient*` 的 `dlsym` 取不到，或 `CopyEvent` 返回 nil | 全程 dlopen + dlsym，失败即整块降级为 nil（温度隐藏），不抛错、不崩 |
| CPU 功耗不可得 | `CPU Energy` / `EACC_CPU` / `PACC*_CPU` / `DRAM0` / `ANE0` 连续 3 轮全为 0 | 不做 CPU 功耗；功耗区只给 GPU ≈3.2 W + SoC 温度 |
| powermetrics 需 root | 非 root 直接 exit 1 | 不调起、不提权、不做常驻 |
| SMC 协议已变 | 旧 smc.c 布局 `selector=2` → `0xe00002c2` | 放弃 SMC 温度路线，改走 IOHID |
| 压力事件型 API | `DispatchSource.makeMemoryPressureSource` 只在变化时投递，首帧 `level=-1` | 轮询用 sysctl；DispatchSource 只做事件补充 |

## 五、本机不可得项与后续待办

| 项 | 现状 | 后续 |
|---|---|---|
| 风扇转速 | SMC 键路径不存在（只暴露 `AppleSMCKeysEndpoint`），IOHID 未暴露风扇传感器 | 下一轮试 `AppleSMCSensorDispatcher` 与 IOReport 风扇相关 group；确认不可得则 UI 不出该项 |
| GPU 功耗（IOReport） | 已能读（空闲 ≈3.2 W），但单位为推断（nJ），`PWRCTRL`/`GPUPH` 是驻留语义 | 用 `powermetrics`（需 root，仅校准用）或 istats 对照一次，UI 标注「估算」 |
| CPU 频率 | 「CPU Stats」组存在（22 channels），本次未解析出每核频率数值 | 补跑 `probe_ioreport2` 的 CPU Stats 段，解析每核 P0..Pn 驻留 |
| Intel 侧 | 全部结论为知识推断，无 Intel 机器实测 | 键名同名可在 Intel 复用（`Device/Renderer Utilization %`）；温度只走 IOHID 路线待验证 |
| `AppleSMCKeysEndpoint` 新协议 | 未逆向 | 仅当确需风扇/电流等 SMC 独有指标时才投入；本期不做 |
| 与菜单栏 UI 结合的刷新策略 | 未定（CPU 权力器 vs 定时器） | 按实测开销：CPU/内存/磁盘 1 s、GPU 1 s、温度 5 s，全部在本线程外采样 |
