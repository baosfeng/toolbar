import CoreGraphics

// MARK: - 符号图缓存键（纯字符串口径）

/// 符号图缓存键 —— 键的构成规则单独放这里，便于断言「同输入必同键、异输入必异键」
///
/// 为什么键里只有 (符号名, 点尺寸, 颜色描述)：palette 着色图在**绘制时**才按当前外观解析
/// （实测同一张配置图在浅 / 深外观下绘制结果不同），因此键不需要带外观；
/// 而点尺寸按 0.01 取整，避免 12 与 12.000001 这类浮点抖动分裂出两份缓存。
public enum DrawnSymbolCacheKey {

    /// 命名符号图的键
    public static func symbol(name: String, pointSize: CGFloat, colorDescription: String) -> String {
        name + "|" + String(format: "%.2f", pointSize) + "|" + colorDescription
    }
}
