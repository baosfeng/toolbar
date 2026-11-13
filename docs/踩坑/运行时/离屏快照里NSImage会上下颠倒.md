# 离屏快照里 NSImage 会上下颠倒

> **何时阅读：** 用 `cacheDisplay` 抓离屏截图取证明明画面正常、截出来的图里图片却是倒的（镜像 / 180° 旋转）。

## 现象

离屏取证截图（`MenuPanelSnapshot` / `SnipToolBarSnapshot` 这类 `bitmapImageRepForCachingDisplay` + `cacheDisplay` 路径）里，卡片上的缩略图上下颠倒；同一张原图与落盘缩略图文件本身都是正的。剪贴板卡片与截图工具条都见过。

## 原因

- 卡片视图 `ClipboardCardView` 是翻转坐标系（`isFlipped = true`，`ClipboardCardView.swift`）。
- `NSImage.draw(in:from:operation:fraction:)` 的默认 `respectFlipped` 为 **false**，在翻转上下文里按未翻转坐标系绘制（`ClipboardCardView+Resources.drawAspectFill`）。
- 屏幕合成路径会正确处理这一差异，`cacheDisplay` 则把像素原样写进位图 → 翻转被"暴露"出来。

实测（同一张 PNG 配同一份 `drawAspectFill`，独立脚本复现）：`isFlipped = false` 的视图抓出正立；`isFlipped = true` 抓出上下颠倒；改成 `respectFlipped: true` 后同一 flipped 视图也能抓出正立。像素均值的上下带互换、左右列均值相等，说明是上下翻转而非左右镜像。

## 处置

- **取证截图里看到图倒着，先怀疑抓图路径，不要改产品绘制代码**。
- 要修只有两条路，互斥：① 给取证渲染器换成 `respectFlipped: true` 的绘制参数（只影响快照工具）；② 给 `drawAspectFill` 加 `respectFlipped: true`（会影响真机上的颜色叠加与位置，必须单独评估与验证）。
- 真机上是否同现象未做实机抓屏取证，别把「离屏截图倒着」直接记成产品缺陷。
