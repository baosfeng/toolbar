# OSLog 的 public 字段任何本机进程都能读

> **何时阅读：** 往日志里写路径、凭据、配对码、用户内容之前。

## 问题描述

本项目的 `OSLogLogger` 一律用 `"%{public}@"` 输出（为了让 `log show` 免 `--info`
也能读到全文）。**public 字段不需要特权**：任何本机进程执行

```bash
log show --last 3h --predicate 'subsystem == "com.networkmonitor"'
```

即可读到全部内容。所以「写日志」等于「广播给本机所有进程」。

历史上确实写进去过：

- 4 位配对 PIN（`TransferService` 收到未配对 offer 时）——泄漏即等于泄漏配对凭据；
- 用户主目录绝对路径（数据库、接收目录、贴图/截图保存路径、DSH 会话文件）。

## 解决方案

进入日志前一律过 `LogRedaction`（`NetworkMonitorCore/Infrastructure/Logging/LogRedaction.swift`）：

| 内容 | 处理 | 为什么 |
|---|---|---|
| 用户路径 | `LogRedaction.path` → 主目录前缀换成 `~` | 保留目录结构便于排查，只隐去用户名 |
| 配对 PIN | `LogRedaction.pin` → 只报位数 | 4 位码留前 2 位等于泄露一半搜索空间 |
| API Key / cookie | `LogRedaction.secret` → 只留末 4 位 | 够核对是哪一条，不足以冒用 |

另外 `OSLogLogger` 默认 `minLevel` 应为 `.info`（类文档写的就是「生产只记 info 及以上」），
`.debug` 会把剪贴板采集这类高频日志全量落盘，既涨体积也放大暴露面。

## 如何识别

- 新增日志里有 `\(someURL.path)` / `\(pin)` / `\(token)`；
- 排查时发现日志里能看到完整用户名或家目录结构——说明脱敏没接上。

## 参考文件

- `NetworkMonitorCore/Infrastructure/Logging/Loggers.swift`、`LogRedaction.swift`
- `TestRunner/LogRedactionTests.swift`
