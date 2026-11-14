# 快照取证必须打包成 .app 运行

> 何时阅读：用 `NM_SNAPSHOT_DIR` 出菜单面板取证图、或写新的 DEBUG 快照钩子时。

## 症状

直接跑 SwiftPM 构建产物：

```bash
NM_SNAPSHOT_DIR=/tmp/nm-shots .build/arm64-apple-macosx/debug/NetworkMonitor
```

进程在启动阶段直接崩，日志最后一行是：

```
bundleProxyForCurrentProcess is nil
```

或 `bundleProxyForCurrentLocation is nil`（`UserNotifications` 初始化处）。
**没有任何截图产出**，`/tmp/nm-shots` 是空的或只有半套。

## 原因

裸二进制没有 `Info.plist`、没有 bundle 目录结构，`Bundle.main` 拿不到可用的 bundle proxy。
项目里有若干处在初始化阶段就要读 bundle 的东西：

- `UserNotifications`（额度提醒）
- `NSWorkspace` 图标解析（进程清单的 App 图标）
- 任何走 `Bundle.main.object(forInfoDictionaryKey:)` 的版本号 / 名称读取

SwiftPM 的 `swift run` 与 `.build/.../NetworkMonitor` 都跑在「无 bundle」状态，
所以**所有走 bundle 的初始化都会在取图上一步炸掉**。

## 做法

先打包成 .app，再跑包内可执行文件：

```bash
cd NetworkMonitor
SKIP_INSTALL=1 ./Scripts/build-app.sh debug        # 产出 dist/一览.app，不装 /Applications
NM_SNAPSHOT_DIR=/tmp/nm-shots ./dist/一览.app/Contents/MacOS/一览
ls /tmp/nm-shots                                   # 出图
rm -rf dist                                        # 取证后清掉
```

`SKIP_INSTALL=1` 是关键：不传它会部署到 `/Applications` 并自动启动，取证机器上会多出一个常驻实例。

## 反例

- 看到「崩了」先去怀疑快照钩子代码：**先确认是不是裸二进制**。钩子没问题，是 bundle 缺失。
- 用 `open dist/一览.app` 代替直接跑可执行文件：LaunchServices 会丢弃 stdout，
  `NM_SNAPSHOT_DIR` 也传不进 GUI 进程的环境，图仍然出不来。
- 取证后忘记删 `dist/`：它体积不小，且会被误当成发布产物。

## 如何识别

看崩溃前最后一条日志。`bundleProxyForCurrentProcess` / `bundleProxyForCurrentLocation`
这类字样一出现，就是跑错了产物形态，不是代码 bug。

## 参考

- [构建与测试](../../开发指南/构建与测试.md)
- 系统页七态取证矩阵（full / empty / nogpu / pressure / load / battery / noproc）见
  [系统监控设计规格](../../设计/系统监控-设计规格.md)
