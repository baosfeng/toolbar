# @MainActor 类适配 nonisolated 协议需要 @preconcurrency

## 问题描述

`@MainActor` 标注的类（如 `EventMonitor`、`NetworkSpeedMonitor`、`ProcessNetworkMonitor`）在适配非 isolated 的协议（如 `EventMonitoringService`、`NetworkMonitoringService`）时，Swift 6 会报 `ConformanceIsolation` 错误：

```
error: conformance of 'EventMonitor' to protocol 'EventMonitoringService' crosses into
main actor-isolated code and can cause data races
```

## 解决方案

在协议名称前添加 `@preconcurrency` 标记：

```swift
@MainActor
final class EventMonitor: @preconcurrency EventMonitoringService {
    // ...
}
```

## 说明

- `@preconcurrency` 告诉编译器将此一致性降级为运行时检查，而非编译时强制
- 适用于 `@MainActor` 类适配 UI 无关但可能在任意 actor 上使用的协议
- 如果协议本身也标记 `@MainActor`，则不需要 `@preconcurrency`

## 参考文件

- `NetworkMonitor/Sources/NetworkMonitor/EventMonitor.swift`
- `NetworkMonitor/Sources/NetworkMonitor/NetworkMonitor.swift`
- `NetworkMonitor/Sources/NetworkMonitor/AppCoordinator.swift`
- `NetworkMonitor/Sources/NetworkMonitorCore/Domain/Protocols/EventMonitoringService.swift`
