# @Sendable 闭包标志位用锁盒承载

## 问题描述

测试里在 `@Sendable` 回调闭包中写外层的 `var received` 标志位，Swift 6 严格并发报 `mutation of captured var 'received' in concurrently-executing code`。本轮清零的 43 条编译告警里有 6 条属于这一类（`CoreConfigTests` 4 条、`ClipboardThumbnailGateTests` 2 条，清单见 [编译警告清单](../../调研/编译警告清单.md)）。

改成 `nonisolated(unsafe) var` 只是把检查关掉：断言线程与回调线程仍是无保护读写，测试会在负载高时随机红。

## 触发条件

1. 闭包被要求 `@Sendable`：`NotificationCenter.addObserver(forName:object:queue:using:)`、`DispatchQueue.async`、`Task.detached`、`withTaskGroup` 等；
2. 闭包内要写闭包外的可变状态（典型是「事件是否已收到」这类测试标志位）；
3. 断言处与回调处都会访问它。

## 解决方案

把标志位放进 `OSAllocatedUnfairLock` 锁盒——锁盒本身 `Sendable`，不需要 `@unchecked Sendable` 断言，也不必把测试函数整体改成 `@MainActor`（改 actor 会顺带改回调时序，掩盖真正要测的派发行为）。

```swift
let received = OSAllocatedUnfairLock(initialState: false)
let observer = NotificationCenter.default.addObserver(
    forName: AppEvents.clipboardChanged, object: nil, queue: nil
) { _ in
    received.withLock { $0 = true }
}
AppEvents.postClipboardChanged()
NotificationCenter.default.removeObserver(observer)
assertEqual(received.withLock { $0 }, true, "clipboardChanged 事件已发布并接收")
```

要带值出来时同样用锁盒；值是对象（`Notification` 非 `Sendable`）就先在外面取值，再让内层闭包只捕获 `String?`：

```swift
let receivedHash = OSAllocatedUnfairLock<String?>(initialState: nil)
... { notification in
    let hash = notification.userInfo?[AppEvents.clipboardThumbnailHashKey] as? String
    receivedHash.withLock { $0 = hash }
}
```

## 并发隔离诊断顺序

按「改动面从小到大」试，不要一上来就包 `assumeIsolated`：

1. **先看能不能 `nonisolated`**：纯计算、只依赖入参的静态方法（如 `SystemMonitor.merging(thermal:powerWatts:)`）标 `nonisolated` 最省事，不动调用时序。
2. **再加 `@MainActor`**：确实需要主 actor 状态时才加，代价是整条调用链被拉进主 actor。
3. **最后才用 `MainActor.assumeIsolated`**：它是**运行时断言**，不是隔离转换——只在「闭包确实在主线程同步回调」成立时安全，在后台队列上用会直接崩。所以只在有 AppKit / CAAnimation / EventTap 文档依据的主线程回调里用：`SnipFailureNotice`（`runAnimationGroup` 的 completionHandler）、`MotionKit` / `TransferMotion`（CAAnimation 完成回调）、`HotKeyRegistry` / `GlobalHotKey`（事件 tap 主 runloop）、`PinWindowController`（`DispatchQueue.main.async` 内）；没有依据的地方改用 `Task { @MainActor in ... }`。

## 参考文件

- `NetworkMonitor/Sources/TestRunner/CoreConfigTests.swift:39,52,65,78`
- `NetworkMonitor/Sources/TestRunner/ClipboardThumbnailGateTests.swift:77,90`
- `NetworkMonitor/Sources/NetworkMonitor/SystemMetrics/SystemMonitor.swift:224`
- `NetworkMonitor/Sources/NetworkMonitor/Snip/SnipFailureNotice.swift:70-77`
- `NetworkMonitor/Sources/NetworkMonitor/Motion/MotionKit.swift:73-103`、`NetworkMonitor/Sources/NetworkMonitor/Transfer/TransferMotion.swift:52-78`
- `NetworkMonitor/Sources/NetworkMonitor/Pin/PinWindowController.swift:49`
