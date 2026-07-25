# os_log_with_type 宏在 Swift 中不可用

## 问题描述

在 Swift 中直接使用 C 宏 `os_log_with_type` 会导致编译错误：

```
error: cannot find 'os_log_with_type' in scope
note: macro 'os_log_with_type' unavailable: function like macros not supported
```

## 解决方案

使用 Swift 原生的 `os_log` 函数 API：

```swift
// ❌ 错误 - C 宏不可用
os_log_with_type(osLog, osLogType, "%{public}@", message)

// ✅ 正确 - Swift 原生 API
os_log(osLogType, log: osLog, "%{public}@", message)
```

需要 `import OSLog`（macOS 10.15+）。

## 参考文件

- `NetworkMonitor/Sources/NetworkMonitorCore/Infrastructure/Logging/Loggers.swift`
