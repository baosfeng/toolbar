import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 来源 App 主题色与头带对比度（纯逻辑）

/// 卡片头带按来源染色的口径守卫：命中 / 回落 / 头带几何 / 黑白墨色对比度
///
/// 背景：头带底色与文字色如果只写在视图里就取不到，测试够不着；
/// 因此色表、取色与对比度全部收敛到 `SourceAppPalette`，这里逐项钉住。
func runSourceAppPaletteTests() {
    print("🧪 Testing source app palette...")

    // 命中：bundleID 优先，大小写不敏感
    let safari = SourceAppPalette.tint(bundleID: "com.apple.Safari", appName: "Safari")
    assertEqual(safari.isFallback, false, "Safari 命中内置色表")
    assertEqual(safari.color.hexString, "#0068D9", "Safari 取品牌蓝")
    let wechatUpper = SourceAppPalette.tint(bundleID: "com.tencent.xinWeChat", appName: nil)
    assertEqual(wechatUpper.color.hexString, "#07C160", "bundleID 大小写不敏感，微信取品牌绿")

    // 命中：bundleID 缺失时退回 App 名（中英文别名都认）
    assertEqual(SourceAppPalette.tint(bundleID: nil, appName: "终端").color.hexString,
                "#1C1C1E", "中文别名「终端」命中 Terminal")
    assertEqual(SourceAppPalette.tint(bundleID: nil, appName: "VS Code").color.hexString,
                "#007ACC", "带空格的别名按小写全等命中")

    // 回落：未知来源 / 空入参都给主题带底色，且标记 isFallback
    let unknown = SourceAppPalette.tint(bundleID: "com.example.Unknown", appName: "未知 App")
    assertEqual(unknown.isFallback, true, "未知来源标记回落")
    assertEqual(unknown.color, SourceAppPalette.fallbackColor(isDark: false), "未知来源回落浅色带底")
    assertEqual(SourceAppPalette.tint(bundleID: nil, appName: "  ").isFallback, true, "空白入参按未知来源回落")
    assertEqual(SourceAppPalette.tint(bundleID: nil, appName: nil, isDark: true).color,
                SourceAppPalette.fallbackColor(isDark: true), "深色外观回落深色带底")

    // 头带几何：贴卡片上沿、与内容区同宽
    let bounds = CGRect(x: 0, y: 0, width: 176, height: 198)
    let band = ClipboardCardGeometry.headBandRect(in: bounds)
    assertEqual(band, CGRect(x: 0, y: 0, width: 176, height: ClipboardCardGeometry.headBandHeight),
                "头带贴顶与卡同宽，高度取卡头令牌")
    assertEqual(ClipboardCardGeometry.headBandHeight, 26,
                "卡头 26pt：20pt 认不出来源、32pt 放不下相对时间（见 paste-r2 定稿）")

    // 对比度：WCAG 公式的口径（黑白 21:1、同色 1:1、顺序无关）
    assertEqual(SourceAppPalette.contrastRatio(.init(hex: 0x000000), .init(hex: 0xFFFFFF)), 21,
                "黑白对比度 21:1")
    assertEqual(SourceAppPalette.contrastRatio(.init(hex: 0x777777), .init(hex: 0x777777)), 1,
                "同色对比度 1:1")
    assertEqual(SourceAppPalette.contrastRatio(.init(hex: 0xFFFFFF), .init(hex: 0x000000)), 21,
                "对比度与参数顺序无关")

    // 头带文字：每个内置来源取黑 / 白后都不得低于 WCAG AA 4.5:1
    for source in SourceAppPalette.sources {
        let ink = SourceAppPalette.ink(on: source.color)
        assertEqual(ink.ratio >= 4.5, true,
                    "\(source.bundleID) 头带文字对比度 \(ink.ratio) 达到 4.5:1")
    }
}
