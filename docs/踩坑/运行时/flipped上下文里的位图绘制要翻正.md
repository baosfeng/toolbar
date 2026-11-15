# flipped 上下文里的位图绘制要翻正

> **何时阅读：** 自绘视图（`isFlipped = true`）里画图片 / 图标，结果图上下颠倒了；
> 或者在纠结「整段 draw 要不要翻」，担心翻完之后文字也反了。

## 现象

剪贴板卡片的缩略图与被粘贴文件的来源 App 图标，在 flipped 卡片视图里画出来是**上下颠倒**的：
图片内容像是被垂直镜像了一次，卡片文字与元信息行却完全正常。
用离屏取样比对（同一张原图，比较画面上下两半的平均色）能确认是上下翻转而非左右镜像：上下带的均值互换、左右列的均值相等。

## 判据

同一个 flipped 绘图上下文里，两类绘制的行为**不一致**：

| 绘制 | 在 flipped 上下文里的表现 |
|------|--------------------------|
| 文字（CoreText / `NSAttributedString.draw`） | 会自行翻正，直接画就是正的 |
| 位图（`NSImage.draw(in:from:operation:fraction:)`） | **不做坐标补偿**，直接画就是上下颠倒 |

于是「整段 `draw` 外面套一次翻正」这条路是错的：文字会被一起翻过去。翻正只能挡在位图那一处。

顺带区分两个容易混的重载：`NSImage.draw(in:)` 会自己处理翻转，`draw(in:from:operation:fraction:)` 不会——
需要控制裁剪源与合成模式（等比填充、叠加）时只能走后者，也就必须自己补这一下。

## 绕法

翻正量收在一个纯函数里，绘制原语只负责施加：

- `DrawnUnflip.transform(around:contextIsFlipped:)`（`NetworkMonitorUI`）给出目标矩形中线上的纵向镜像变换，上下文本来就不是 flipped 时返回 `nil`；
- `DrawnInk.withUnflippedIfNeeded(around:)`（`DrawnUI/DrawnUIKit.swift`）取当前 `NSGraphicsContext.isFlipped`，拿到变换就 `saveGState` → `concatenate` → 绘制 → `restoreGState`，拿不到就原样绘制。

```swift
DrawnInk.withUnflippedIfNeeded(around: target) {
    image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
}
```

当前接入点：剪贴板卡片缩略图（`ClipboardCardView+Resources.drawAspectFill`）与文件条目的来源 App 图标（`ClipboardCardView+Content`）。

## 验证

视觉判断容易被「这张图本来就该是倒的吗」干扰，改用离屏取样：

1. 把同一张有明显上下差异的原图，用两种上下文各渲染一次（`isFlipped` 真 / 假）；
2. 分别取渲染结果的上下两带平均色，翻正前后的两组值应当互换；
3. 再取左右两列平均色，应当相等（证明是上下翻转而不是镜像）。

文字不需要参与这个比对——它本来就由 CoreText 翻正，比对时以它为参照，能看出「只有位图反了」。

## 参考文件

- `NetworkMonitor/Sources/NetworkMonitorUI/DrawnUnflip.swift`（镜像变换与 `needsFlip` 判定）
- `NetworkMonitor/Sources/NetworkMonitor/DrawnUI/DrawnUIKit.swift`（`withUnflippedIfNeeded`）
- `NetworkMonitor/Sources/NetworkMonitor/Clipboard/ClipboardCardView+Resources.swift`（`drawAspectFill` 接入）
- [离屏快照里 NSImage 会上下颠倒](离屏快照里NSImage会上下颠倒.md) — 同一个翻转现象的「取证路径」视角（离屏截图才暴露，先怀疑抓图而不是产品绘制）
