# @unchecked Sendable 标记需求

## 问题描述

`UdpDiscoveryService`、`HarnessUsageService`、`UserDefaultsStorage` 等类有 `var` 可变属性（`heartbeatTimer`、`receiveFD` / `sendFD`、缓存等），在以 `: Sendable` 协议出现时需要标记 `@unchecked Sendable`。

## 触发条件

Swift 6 严格并发模式下，当一个类：
1. 遵循了 `Sendable` 协议（直接或通过协议继承）
2. 含有 `var` 可变存储属性
3. 内部通过串行队列 / actor 保证线程安全（编译器无法验证）

## 解决方案

```swift
// 改为 @unchecked Sendable，前提是内部已通过串行队列保证线程安全
public final class UdpDiscoveryService: @unchecked Sendable {
    private var heartbeatTimer: DispatchSourceTimer?  // 可变，但在内部串行队列上访问
}
```

## 参考文件

- `NetworkMonitor/Sources/NetworkMonitorCore/Transfer/Discovery/UdpDiscoveryService.swift`（socket 状态 + 串行队列）
- `NetworkMonitor/Sources/NetworkMonitorCore/Harness/HarnessUsageService.swift`（索引状态 + 串行队列）
- `NetworkMonitor/Sources/NetworkMonitorCore/Infrastructure/Storage/UserDefaultsStorage.swift`（偏好缓存 + 锁）
