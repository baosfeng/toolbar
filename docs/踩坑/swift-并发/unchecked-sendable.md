# @unchecked Sendable 标记需求

## 问题描述

`SystemSampler`、`ReasonixHookMonitor`、`KeyPressMonitor` 等类有 `var` 可变属性（`timer`、`socketFd`、`monitor` 等），在以 `: Sendable` 协议出现时需要标记 `@unchecked Sendable`。

## 触发条件

Swift 6 严格并发模式下，当一个类：
1. 遵循了 `Sendable` 协议（直接或通过协议继承）
2. 含有 `var` 可变存储属性
3. 内部通过串行队列 / actor 保证线程安全（编译器无法验证）

## 解决方案

```swift
// 改为 @unchecked Sendable，前提是内部已通过串行队列保证线程安全
public final class SystemSampler: @unchecked Sendable, SystemSamplingService {
    private var timer: DispatchSourceTimer?  // 可变，但在串行队列上访问
}
```

## 参考文件

- `NetworkMonitor/Sources/NetworkMonitorCore/SystemSampler.swift`
- `NetworkMonitor/Sources/NetworkMonitor/ReasonixHookMonitor.swift`
- `NetworkMonitor/Sources/NetworkMonitor/KeyPressMonitor.swift`
- `NetworkMonitor/Sources/NetworkMonitorCore/Infrastructure/Storage/UserDefaultsStorage.swift`
