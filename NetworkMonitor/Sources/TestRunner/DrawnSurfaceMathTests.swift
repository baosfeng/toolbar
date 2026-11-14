import CoreGraphics
import Foundation
import NetworkMonitorUI

// MARK: - 绘制层纯口径（表面层 / 阴影 / 焦点环 / 符号键 / 读屏文案）

/// 绘制层里「能算出来的那部分」的守卫：层不透明度折叠、阴影换算、焦点环路径、缓存键、读屏文案
///
/// 绘制本身（CGContext / NSBezierPath 落笔）在可执行 target 里，TestRunner 无法 import；
/// 因此把这些绘制实现里的**换算式与拼接规则**抽到 NetworkMonitorUI 用纯值断言，
/// 落笔结果由离屏快照逐像素对比自证（见 docs/设计/自绘组件库.md 的验收方式）。
func runDrawnSurfaceMathTests() {
    print("🧪 Testing drawn surface math (layer alpha / shadow / focus ring / cache key / a11y text)...")

    // MARK: 层不透明度折叠

    assertEqual(DrawnLayerAlpha.fold(0.72, layer: 1), 0.72, "常态层：不改变颜色自带 alpha")
    assertEqual(DrawnLayerAlpha.fold(0.06, layer: 0.5), 0.03, "过渡半程：按层不透明度折半")
    assertEqual(DrawnLayerAlpha.fold(0.05, layer: 0), 0, "层不透明度 0 → 整层透明")
    assertEqual(DrawnLayerAlpha.isVisible(0), false, "0 不画")
    assertEqual(DrawnLayerAlpha.isVisible(0.001), false, "刚好 0.001 不画（阈值是开区间）")
    assertEqual(DrawnLayerAlpha.isVisible(0.0011), true, "刚过阈值就画")
    assertEqual(DrawnLayerAlpha.isVisible(1), true, "常态层要画")

    // MARK: 阴影换算

    let shadowAlpha = DrawnShadowMath.shadowAlpha(opacity: 0.12, contentAlpha: 0.72)
    assertEqual(abs(shadowAlpha - 1.0 / 6.0) < 1e-9, true,
                "阴影不透明度反算：0.12 / 0.72 = 1/6（内容 alpha 打折后仍等于 0.12）")
    assertEqual(DrawnShadowMath.shadowAlpha(opacity: 0.12, contentAlpha: 0), 0,
                "内容全透明时阴影强度归零（不能除出无穷大）")
    assertEqual(DrawnShadowMath.blur(visibleRadius: 6), 12,
                "可见扩散半径 6 → CG 模糊核 12（CALayer 与 CGContext 约 2 倍关系）")
    assertEqual(DrawnShadowMath.shapeRect(for: CGRect(x: 10, y: 20, width: 100, height: 50), inset: 0.5),
                CGRect(x: 10.5, y: 20.5, width: 99, height: 49),
                "阴影形状矩形按半像素内缩")

    // MARK: 焦点环路径

    assertEqual(DrawnFocusRingMath.rowRect(for: CGRect(x: 0, y: 28, width: 296, height: 28)),
                CGRect(x: 1, y: 29.5, width: 294, height: 25),
                "行内焦点环：横向内缩 1、纵向内缩 1.5")
    assertEqual(DrawnFocusRingMath.cardRect(for: CGRect(x: 0, y: 0, width: 296, height: 120)),
                CGRect(x: 1, y: 1, width: 294, height: 118),
                "整卡焦点环：四周内缩 1")
    assertEqual(DrawnFocusRingMath.cardRadius(9), 8, "整卡焦点环圆角 = 卡圆角 − 1")
    assertEqual(DrawnFocusRingMath.cardRadius(0.5), 0, "卡圆角小于 1 时不出现负圆角")

    // MARK: 符号图缓存键

    let key = DrawnSymbolCacheKey.symbol(name: "star.fill", pointSize: 12,
                                         colorDescription: "Catalog color: System yellowColor")
    assertEqual(key, DrawnSymbolCacheKey.symbol(name: "star.fill", pointSize: 12,
                                                colorDescription: "Catalog color: System yellowColor"),
                "同输入 → 同键（缓存命中）")
    assertEqual(DrawnSymbolCacheKey.symbol(name: "star", pointSize: 12, colorDescription: "c")
                == DrawnSymbolCacheKey.symbol(name: "star.fill", pointSize: 12, colorDescription: "c"),
                false, "符号名不同 → 不同键")
    assertEqual(DrawnSymbolCacheKey.symbol(name: "star", pointSize: 12, colorDescription: "c")
                == DrawnSymbolCacheKey.symbol(name: "star", pointSize: 14, colorDescription: "c"),
                false, "点尺寸不同 → 不同键")
    assertEqual(DrawnSymbolCacheKey.symbol(name: "star", pointSize: 12, colorDescription: "c")
                == DrawnSymbolCacheKey.symbol(name: "star", pointSize: 12, colorDescription: "d"),
                false, "着色不同 → 不同键")
    assertEqual(DrawnSymbolCacheKey.symbol(name: "star", pointSize: 12, colorDescription: "c")
                == DrawnSymbolCacheKey.symbol(name: "star", pointSize: 12.001, colorDescription: "c"),
                true, "点尺寸按 0.01 取整：浮点抖动不分裂缓存")

    // MARK: 读屏文案

    assertEqual(DrawnAccessibilityText.row(title: "未缓存输入", value: "1.24M",
                                           secondary: "62%", detail: "会话 3"),
                "未缓存输入 1.24M 62% 会话 3", "两行式四段全念")
    assertEqual(DrawnAccessibilityText.row(title: "下载", value: "1.2M", secondary: "", detail: ""),
                "下载 1.2M", "空段不念（不留多余空格）")
    assertEqual(DrawnAccessibilityText.row(title: "", value: "", secondary: "", detail: ""),
                "", "全空不念")
}
