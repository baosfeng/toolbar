# release 构建暴露被 DEBUG 块包住的生产方法

> **何时阅读：** 本地 `swift build` 全绿但 tag 触发的 Release 工作流在打包步骤失败时。

## 现象

- 本地 `swift build --disable-sandbox --build-system native`（debug）通过、TestRunner 全绿；
- push `v1.7.0` tag 后 GitHub Release 工作流的 `Package .app` job 退出码 1，日志里唯一编译错误是：
  `SnipController+HotKeys.swift:171: value of type 'SnipOverlayView' has no member 'selectFullBoard'`。

## 原因

`selectFullBoard()` 是白板模式的**生产路径**方法，却被写在 `SnipOverlayView+Actions.swift` 的 `#if DEBUG` 块里（夹在两个 debug 取证方法之间）。
debug 构建能编过，是因为块被保留；release 构建（`-c release`，无 `-D DEBUG`）里方法被裁掉，调用点立即编译失败。

## 排查路径

1. `ghops actions logs <repo> <run> --jobs` 找到失败 job；
2. `ghops actions logs <repo> <run> --job "Package .app" | grep -iE 'error:'` —— 完整日志尾部只有 warning，真正的错误在中间；
3. 本地用同一种构建方式复现：`swift build -c release --disable-sandbox --build-system native`（**不要只跑 debug**）。

## 修复与预防

- 修复：把 `selectFullBoard()` 移到 `#if DEBUG` 块外，并在方法注释里写明「不能放进 DEBUG 块」；
- 预防：CI 的 `ci.yml` 增加一步 release 构建门禁（`swift build -c release --disable-sandbox`），
  避免「debug 绿、release 红」再次拖到发版才暴露。
