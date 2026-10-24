# Swift 扩展不能声明存储属性

> **何时阅读：** 为了守住单文件 500 行 / 15 KiB 门禁，把类拆成「主类 + 扩展文件」时编译报错。

## 问题描述

把主类里一批方法挪到 `类名+职责.swift` 的 `extension` 里，编译报两类错：

1. `extensions must not contain stored properties` —— 迁移时把带 `var`/`let` 的存储属性也带进去了
2. `'xxx' is inaccessible due to 'private' protection level` —— 扩展文件访问主类的 `private` 成员

还有一个更隐蔽的：`override` 方法能不能留在扩展里，取决于它是不是 `@objc` 方法。

## 触发条件

- 拆分文件时按「代码块」而不是按「成员类型 + 可见性」切
- 主类成员原本是 `private` / `private(set)`，扩展在另一个文件

## 解决方案

1. **存储属性一律留在主类**。扩展文件里只能有方法（含 `static let` 常量以外的计算属性）。
2. **跨文件访问的成员放宽为 internal**，并在注释里写清原因，例如：

   ```swift
   /// 放宽为 internal：绘制扩展文件需要读取
   private(set) var screenshot: CGImage
   ```

3. **`override` 方法也留在主类**（`draw(_:)`、`keyDown(with:)` 等）。把被它们调用的辅助方法挪出去即可，辅助方法在扩展里保持 internal 就能被调用。
4. 拆分后跑一次 `bash NetworkMonitor/Scripts/check-file-size.sh`，避免拆完一半又超。

## 如何识别

- `extensions must not contain stored properties` → 找出迁移段里的 `var`/`let` 搬回主类
- `is inaccessible due to 'private'` → 逐个放宽，别图省事整类改 public
- 拆分后行为异常但编译通过 → 检查是不是把 `override` 挪走了

## 参考文件

- `.agents/skills/toolbar-coding-standards/SKILL.md`「3. 单一职责」
- `NetworkMonitor/Sources/NetworkMonitor/Snip/SnipOverlayView.swift` 与 `SnipOverlayView+Drawing.swift`、`SnipOverlayView+Actions.swift`、`SnipOverlayView+Annotation.swift`
