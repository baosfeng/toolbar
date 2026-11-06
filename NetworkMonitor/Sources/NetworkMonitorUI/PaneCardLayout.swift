import Foundation

// MARK: - 两页共用卡片语法的纯逻辑部分

/// 卡片层级与间距规则 —— 与 AppKit 无关，供两页共用并被断言
///
/// 令牌数值本身在 `PaneCardStyle`（AppKit 侧转成 NSColor / NSFont）；
/// 这里只放「按 N 个元素选哪种排布」这类判据，避免两边各写一遍 if。
public enum PaneCardLayout {

    /// 额度族格列数：provider 给 1–3 个窗口时都用满可用宽
    ///
    /// - Parameter windowCount: 该 provider 的额度窗口数
    /// - Returns: 1–3；0 个窗口时返回 0（调用方整行隐藏）
    public static func limitColumns(windowCount: Int) -> Int {
        min(max(windowCount, 0), 3)
    }

    /// 额度族格是否走「窄格」排法（角标与重置时间分行）
    ///
    /// 与 `BillingLimitLayout.isCompact` 同一判据（三列时必须分行），
    /// 这里复制一份是因为本 target 不依赖 Core；两处取值必须一致。
    public static func isCompactCell(columnCount: Int) -> Bool {
        columnCount >= 3
    }

    /// 页头是否放得下页级分段控件
    ///
    /// 320pt 浮层内容宽 296pt：主体名 ≤ 96pt 时才能同时容下三段分段与刷新按钮。
    /// - Parameters:
    ///   - nameWidth: 主体名（如「DSH · 1611 会话」）实需宽度
    ///   - segmentWidth: 分段控件实需宽度
    /// - Returns: true = 页头单行容纳全部；false = 主体名尾部省略
    public static func headerFits(nameWidth: CGFloat, segmentWidth: CGFloat) -> Bool {
        let available: CGFloat = 296 - 24 - 6 - 6
        return nameWidth + segmentWidth + 12 <= available
    }
}
