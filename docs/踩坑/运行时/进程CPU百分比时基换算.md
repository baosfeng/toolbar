# 进程 CPU 百分比：mach ticks 时基换算

> **何时阅读：** 接入「进程 CPU Top-N」、看到进程 CPU 占用全是 0.x%、或者怀疑 `proc_pidinfo` 的 CPU 时间单位时。

## 症状

用 `proc_pidinfo(pid, PROC_PIDTASKINFO, ...)` 取 `pti_total_user` + `pti_total_system` 差分算 CPU 百分比，结果**系统性偏小约 42 倍**：

| 场景 | 期望 | 实际（按纳秒换算） |
|---|---|---|
| 单线程满载 | ~100% | ~2.4% |
| 3 线程自旋 | ~300% | **7.2%** |
| Chrome 前台 | 30–40% | <1%，菜单面板几乎永远显示「空闲」 |

这个偏差**不会报错、不会崩溃**，只是数值静默失真，因此极易被当成「本机就是这么闲」而放过。

## 原因

`proc_taskinfo.pti_total_user` / `pti_total_system` 的单位是 **mach absolute time 的 tick**，**不是纳秒**。

在 Intel Mac 上 `mach_timebase_info` 是 `1/1`（1 tick = 1 ns），很多旧代码与博客直接把它当纳秒用也「看起来对」；Apple Silicon 上 timebase 变成 **125/3**，即 **1 tick = 41.6667 ns**，于是同一段代码缩小 41.67 倍。

本机实测：

```
=== mach_timebase_info ===  numer/denom: 125/3   ns per tick: 41.6667
=== 3 线程自旋 0.4 s 实测 ===
  raw delta (pti_total_user+system) = 28612112
  HYPOTHESIS 1: delta is ns          =   7.2%     <- 错！
  HYPOTHESIS 2: delta is mach ticks  = 298.0%     <- 对（期望 ~300%）
```

校准方法就是拿一个已知并发的自旋线程组测：`raw delta × 41.6667 ns = 1.192 s` 的 CPU 时间摊在 0.4 s 墙钟上 = 298%，与 3 线程预期吻合；若按纳秒算就只有 0.0286 s，即 7.2%。

## 正确写法

timebase 每次进程启动取一次即可，之后复用：

```swift
var tb = mach_timebase_info_data_t()
mach_timebase_info(&tb)
let nsPerTick = Double(tb.numer) / Double(tb.denom)      // 本机 41.6667，Intel 机型为 1.0

// deltaTicks = (本次 user+system) - (上次 user+system)，累加结果用 &- 做过期回绕保护
let cpuSeconds = Double(deltaTicks) * nsPerTick / 1e9
let cpuPercent = cpuSeconds / wallSeconds * 100.0
```

要点：

1. **timebase 必须运行时读取**，不能硬编码 41.6667 —— Intel 机型是 1/1，硬编码会让 Intel 上放大 41.67 倍（同样错误，反向）。
2. `wallSeconds` 用 `mach_continuous_time` 或 `Date` 的实测间隔，**不要用采样周期的配置值**：定时器抖动、被系统挂起都会让真实间隔偏离配置值。
3. `cpuPercent` **不要 clamp 到 100**：多线程进程合法地超过 100%，实测 3 线程自旋 298.0%。若 UI 需要 0…1 的进度条，另设一个「归一化到核数」的展示值，别污染原始口径。
4. 首帧只有基线，**必须给 nil 而不是 0** —— 与现有 GPU / 磁盘差分指标的口径一致，写 0 会把「还没测」显示成「完全不忙」。

## 反例（错误写法）

```swift
// ❌ 把 ticks 当纳秒：Apple Silicon 上偏小 41.67 倍
let cpuSeconds = Double(deltaTicks) / 1e9

// ❌ 硬编码 M 系列的 timebase：Intel 机型（timebase=1/1）上反向放大 41.67 倍
let cpuSeconds = Double(deltaTicks) * 41.6667 / 1e9

// ❌ 用配置的采样周期当墙钟：定时器被节流时百分比虚高
let cpuPercent = cpuSeconds / sampleInterval * 100.0

// ❌ clamp 到 100：多线程进程被削平，Top-N 排序错乱
let cpuPercent = min(100.0, raw)
```

## 如何识别

- 单元测试里断言「自旋线程 > 90%」；如果实现错了，断言会得 2%，不会假绿。
- 快速自检：拿一个已知占用（`yes > /dev/null` 单线程）对比 `top -pid` 与自己的读数，比值应接近 1；若是 ~0.024 就是本坑。
- 若读数为 0 且 `proc_pidinfo` 返回 −1，那不是时基问题，是 `proc_taskinfo` 结构体布局写错（96 字节 / 18 字段 / Int32 与 UInt64 混排，Swift 不会自动布局）。

## 参考

- 指标可得性与成本见 [系统监控第二批指标可行性调研](../../调研/系统监控-第二批指标-可行性调研.md) §2.2
- `proc_taskinfo` 结构体与 `_silgen_name` 绑定细节同上
