# IOReport 读取崩溃（SIGSEGV）

> **何时阅读：** 接入 IOReport 取 GPU 功耗 / P-state 驻留 / SoC 电压态时进程段错误；或准备把 IOReport 探针代码搬进 `Sources/` 之前。

## 症状

进程**随机段错误 / BPT trap**，崩溃点分布在 `IOReportMergeChannels`、`IOReportChannelGetGroup`、`CFRelease` 内部，堆栈毫无信息量（全是 CoreFoundation 帧）。同一个程序有时能跑完、有时第一个通道就崩，**与数据内容无关，与调用顺序和引用持有方式有关**。

本机（macOS 27 / M1 Pro）实测三类写法必崩，且都不产生编译告警。

## 三个会崩的用法

### 坑 1：用 nil callback 建 CFMutableDictionary

```swift
// ❌ IOReportMergeChannels 直接 BPT trap
let merged = CFDictionaryCreateMutable(nil, 0, nil, nil)
```

`IOReportMergeChannels` 会对传入字典的 key/value 做 CF 引用操作，callback 为 nil 时按「不做任何 retain/release」的裸指针语义处理，随后内部 `CFRetain` 匿名指针即 trap。

正确做法是显式传 type dictionary callback：

```swift
var merged: CFMutableDictionary!
withUnsafePointer(to: kCFTypeDictionaryKeyCallBacks) { kp in
    withUnsafePointer(to: kCFTypeDictionaryValueCallBacks) { vp in
        merged = CFDictionaryCreateMutable(nil, 0, kp, vp)
    }
}
```

### 坑 2：unsafeBitCast 取通道元素 → CFString 过度释放

```swift
// ❌ 跨函数 / 跨循环复用时崩，通常在后续 IOReportChannelGetGroup 处段错误
let d = unsafeBitCast(CFArrayGetValueAtIndex(arr, i), to: CFDictionary.self)
let name = IOReportChannelGetName(d)     // 返回的 CFString? 稍后被过度释放 → 段错误
```

`CFArrayGetValueAtIndex` 返回的是 **+0 引用**，`unsafeBitCast` 成 `CFDictionary` 后再交给 `IOReportChannelGet*`，其内部把返回值当自己持有的对象管理，导致 CFString 被多 release 一次；下一次访问同一元素即访问已释放内存。

从 `NSDictionary` 临时桥接成 `CFDictionary` 后立刻调用 `IOReportChannelGet*` 是同一类问题的另一种表现，同样崩。

### 坑 3：用 IOReportChannelGetFormat 分派通道类型

`IOReportChannelGetFormat` 存在，但**不要按它分派**：它跟坑 2 有同样的引用问题，且在部分元素上直接崩。

判 simple / state 通道，改用 `IOReportStateGetCount` 的返回值：

```swift
// ✅ simple 通道返回 -1，state 通道返回 >= 2
let isSimple = IOReportStateGetCount(channel) < 0
```

## 唯一稳定写法

**核心原则：通道元素必须持有 `NSDictionary` 强引用，不能只留裸 `CFDictionary`。**

```swift
func channels(_ d: CFDictionary) -> [NSDictionary] {
    guard let holder = (d as NSDictionary)["IOReportChannels"] as? NSArray else { return [] }
    var out: [NSDictionary] = []
    for i in 0..<holder.count {
        out.append(holder.object(at: i) as! NSDictionary)   // 强引用保住 +0 对象
    }
    return out
}
```

配套的两条：

- 订阅组返回的 `CFMutableDictionary` **必须保留强引用**，不能只存局部变量，否则偶发崩。
- **不要**先 `IOReportCopyAllChannels` 再订阅：9225 个通道的订阅必然失败（`IOReportCreateSubscription` 返回 nil），且合并过程本身容易踩坑。必须**按 group 名逐个** `IOReportCopyChannelsInGroup` 之后再 Merge。

## 数据侧的两个相关坑（不崩但会读错）

| 现象 | 原因 | 处置 |
|---|---|---|
| 通道值是 `Int64.min`（`-9223372036854775808`） | 对 state 型通道用了 `IOReportSimpleGetIntegerValue` | 用 `IOReportStateGetCount` 分流；state 通道走 `IOReportStateGet*` 系列 |
| 功耗大 1000 倍 / 小 1000 倍 | 通道单位不统一：同一组里混着 `uJ` / `nJ` / `mJ` | 一律读通道自带 unit 字段换算，**禁止硬编码**；详见[第二批指标调研](../../调研/系统监控-第二批指标-可行性调研.md) §2.1 |

## 如何识别

- 崩溃堆栈里只有 CoreFoundation / CoreFoundation 内部帧、没有自己的函数 → 优先怀疑引用持有问题，而不是数组越界。
- 加 `NSZombieEnabled=1` 重跑，会把「过度释放」变成明确的 `CFString released` 报错。
- 探针阶段验证方法：同一段代码连续跑 100 次（`for i in {1..100}`），崩 1 次就说明引用没持住，不要因为「99 次都过」而上生产。

## 参考

- 指标可得性与成本见 [系统监控第二批指标可行性调研](../../调研/系统监控-第二批指标-可行性调研.md) §2.1 / §2.7 / §2.8
