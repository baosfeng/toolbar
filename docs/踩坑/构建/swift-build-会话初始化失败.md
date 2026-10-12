# swift build 会话初始化失败（本机环境级故障）

> **何时阅读：** 本机 `swift build` / `swift run` 刚启动就失败、而报错与源码无关时。

## 问题描述

本机执行 `swift build` 时，在 session 初始化阶段就立即失败，`exit 1`，关键错误串为：

```
SessionFailedError(... "Unknown error parsing property list")
```

（`...` 为省略的中间字段，关键串是 `Unknown error parsing property list`。）

编译根本还没开始，因此看不到任何与 Swift 源码相关的诊断信息。

## 触发条件

- 本机只安装了 Command Line Tools（本机为 CLT 27），**没有 Xcode.app**
- 默认的 swiftbuild / XCBuild 构建后端在 session 初始化阶段就需要完整 Xcode 环境，于是初始化即失败
- 与构建模式无关：debug、`-c release` 以及任意目标都失败

## 已排除项

以下都试过，均不是原因（同一错误稳定复现）：

- 环境变量干扰
- 全新 HOME 目录
- 4 个 SDK 组合
- `--disable-sandbox` 的有无（带与不带同样失败，该参数与此故障无关）
- git 基线（在干净的基线 worktree 上同样失败，排除项目改动 / 未提交改动导致）
- 用 swift-build shim 绕行

**未检索到匹配该错误串的公开 issue**，因此本文只按「本机环境级故障」记录，不按社区公共缺陷处理。

## 解决方案

### 绕行（当前采用）

所有 `swift build` / `swift run` 命令追加 `--build-system native`：

```bash
cd NetworkMonitor
swift build --disable-sandbox --build-system native
swift build -c release --disable-sandbox --build-system native
swift run --disable-sandbox --build-system native TestRunner
```

- 产物路径不变，仍是 `.build/arm64-apple-macosx/{debug,release}/NetworkMonitor`，`Scripts/build-app.sh` 既有的拷贝逻辑无需改动。
- 副作用：`native` 引擎已被官方标记 deprecated，构建时会多一条 deprecation 警告，可忽略。

### 根治

安装 Xcode.app 后重定向工具链：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

或者重装 / 升级 Command Line Tools。根治之后即可去掉所有 `--build-system native`。

## 一句话提醒

**这不是项目代码问题**：任何一次改动后的构建失败，只要报 `SessionFailedError ... Unknown error parsing property list`，先查本机 Xcode 安装情况，不要当成代码回归去回滚改动。

## 参考文件

- `NetworkMonitor/Scripts/build-app.sh`（已追加该参数）
- [构建与测试](../../开发指南/构建与测试.md)
