# nettop 进程流量漏记

> **何时阅读：** 排查「菜单栏实时网速正常，但活跃进程列表数值极小 / 只显示一两个进程」时。

## 现象

- 菜单栏实时速率 5.9 MB/s，面板「活跃进程」只有 1 条，且是 NetworkMonitor 自己：↓72 B ↑62 B
- 其余进程要么不出现，要么字节数远小于总量

## 根因

`runNettopSnapshot()` 原先调用：

```bash
nettop -P -m tcp -m udp -l 1 -x -n
```

**nettop 的 `-m` 不可叠加**：多次指定时只保留最后一个，等价于 `-m udp`。结果只枚举持有 UDP socket 的进程（本机约 15 个），所有 TCP 流量（浏览器、IM、下载器、Electron 应用）全部缺席。

实测对比（同一时刻、同样本机）：

| 参数 | 进程数 | 说明 |
|------|--------|------|
| `-m tcp -m udp` | 15 | 实际只监控 UDP，Chrome / DeepSeek / curl 全缺失 |
| `-m tcp` | 25 | 只有 TCP |
| 不传 `-m`（默认） | 34 | TCP + UDP，与接口总量吻合 |

第二处问题：即便去掉 `-m`，TCP 模式会追加 `rx_dupe / rx_ooo / re-tx / rtt_avg ...` 等列，原解析器按「末两列是字节数」取 `parts[count-2..count-1]`，会取到 `0 0`，且把数字列拼进进程名导致 PID 解析失败、整行丢弃。

## 修复

```swift
public let nettopSnapshotArguments = ["-P", "-l", "1", "-x", "-n", "-J", "bytes_in,bytes_out"]
```

- 省略 `-m`，走 nettop 默认的 TCP + UDP
- `-J bytes_in,bytes_out` 只保留两列字节数，列数固定，不再受模式追加列影响
- `parseNettopLine` 同时兼容两种布局：带时间戳的默认 `-x` 与无时间戳的 `-J`

## 验证

以同一参数连续采样两次（间隔 3 秒），进程增量之和与 en0 接口增量对比：

```text
en0 delta in=24861157 out=324552 over 3.0s
进程求和   in=24453126 out=234906, 进程数=34   → 偏差 < 2%
```

修复后真机输出（Top 5，含空格进程名解析正确）：

```text
WeChat            pid=1240   ↓16237.2 KB/s ↑13.1 KB/s
DeepSeek Harnes   pid=11301  ↓97.1 KB/s     ↑76.1 KB/s
FastLinkCore      pid=48046  ↓34.6 KB/s     ↑35.1 KB/s
Google Chrome H   pid=89415  ↓22.8 KB/s     ↑0.0 KB/s
```

## 补充说明

- nettop 只统计「有 socket 归属」的进程，内核/无 socket 转发（部分 VPN、utun 隧道）不会出现，进程合计与菜单栏总量有 1%~2% 的天然偏差，属正常
- 非 root 运行 nettop 在部分 macOS 版本上看不到个别进程，属系统权限限制，不是参数问题
