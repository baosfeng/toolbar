import AppKit
import NetworkMonitorUI

// MARK: - 符号绘制 + 缓存

/// SF Symbol 与模板图的绘制 —— 两种画法 + 两处缓存集中在这一处
///
/// 面板里有两种符号用法，之前各写各的：
/// - **行前图标**：外部给图（进程图标 / 模板占位图），等比缩放进方框、模板图按 tint 上色（原 `DrawnRowList+Icon`）；
/// - **符号图**：SF Symbol 按 palette 着色，按自身点尺寸居中（原剪贴板卡片的 `drawSymbol`，每次绘制都重建一张图）。
///
/// 缓存键说明：palette 着色图在**绘制时**才按当前外观解析（实测同一张配置图在浅 / 深外观下绘制结果不同），
/// 因此键只需 (符号名, 点尺寸, 颜色描述)，跨外观复用不会串色；模板图上色的结果按图标对象 + 着色缓存。
@MainActor
public enum DrawnSymbolRun {

    /// 缓存上限（超过即整体清空：符号种类个位数，不做 LRU）
    private static let cacheLimit = 64

    /// 命名符号图缓存（键 = 符号名 | 点尺寸 | 颜色描述）
    private static var symbolCache: [String: NSImage] = [:]

    /// 模板上色图缓存（键 = 图标对象身份 + 着色描述）
    private static var tintCache: [TintKey: NSImage] = [:]

    /// 模板上色缓存的键：图标按对象身份（图标由 AppIconProvider / 符号缓存复用，身份稳定）+ 着色描述
    private struct TintKey: Hashable {
        let image: ObjectIdentifier
        let tint: String
    }

    // MARK: 取图

    /// 按 pointSize + palette 着色生成 SF Symbol（带缓存）
    ///
    /// - Parameters:
    ///   - name: 符号名
    ///   - color: 着色（写进 palette，绘制时按当前外观解析）
    ///   - pointSize: 点尺寸
    public static func symbol(named name: String, color: NSColor, pointSize: CGFloat) -> NSImage? {
        let key = DrawnSymbolCacheKey.symbol(name: name, pointSize: pointSize,
                                             colorDescription: color.description)
        if let hit = symbolCache[key] { return hit }
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let configured = base.withSymbolConfiguration(configuration) ?? base
        if symbolCache.count >= cacheLimit { symbolCache.removeAll(keepingCapacity: true) }
        symbolCache[key] = configured
        return configured
    }

    /// 模板图按 tint 上色（带缓存；非模板图原样返回）
    static func tinted(_ image: NSImage, tint: NSColor?) -> NSImage {
        guard image.isTemplate, let tint else { return image }
        let key = TintKey(image: ObjectIdentifier(image), tint: tint.description)
        if let hit = tintCache[key] { return hit }
        let tinted = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            tint.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        if tintCache.count >= cacheLimit { tintCache.removeAll(keepingCapacity: true) }
        tintCache[key] = tinted
        return tinted
    }

    // MARK: 绘制

    /// 等比缩放进方框并居中（行前图标）：模板图先按 tint 上色
    ///
    /// 自绘不走 `NSImageView.contentTintColor`，模板图原样画出来是纯黑块，故这里必须上色。
    static func drawFitted(_ image: NSImage, in rect: CGRect, tint: NSColor? = nil) {
        guard rect.width > 0, rect.height > 0 else { return }
        let shown = tinted(image, tint: tint)
        let scale = min(rect.width / max(shown.size.width, 1),
                        rect.height / max(shown.size.height, 1))
        let drawRect = CGRect(x: rect.midX - shown.size.width * scale / 2,
                              y: rect.midY - shown.size.height * scale / 2,
                              width: shown.size.width * scale,
                              height: shown.size.height * scale)
        shown.draw(in: drawRect,
                   from: .zero,
                   operation: .sourceOver,
                   fraction: 1,
                   respectFlipped: true,
                   hints: [.interpolation: NSImageInterpolation.high])
    }

    /// 按自身点尺寸居中绘制（符号图）
    ///
    /// 不缩放：符号图自带留白，放大铺满方框会让字形偏粗一档（改造前 `NSImageView`
    /// 的 `.scaleProportionallyUpOrDown` 在 12pt 符号上也是 1:1，实测星形 9×9）。
    public static func drawNative(_ image: NSImage, in rect: CGRect) {
        guard rect.width > 0, rect.height > 0 else { return }
        let size = image.size
        image.draw(in: CGRect(x: rect.midX - size.width / 2,
                              y: rect.midY - size.height / 2,
                              width: size.width,
                              height: size.height))
    }
}
