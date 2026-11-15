import CoreGraphics
import Foundation
import NetworkMonitorCore

// MARK: - 底部详情区口径（纯逻辑）

/// 剪贴板底部详情区 —— 只放数值与文案规则，视图（`ClipboardDetailStripView`）只取数
///
/// 布局（翻转坐标，自上而下）：1pt 分隔线 → 元信息行（右上角小字）→ 正文（最多 3 行，超出内部滚动）。
/// 高度是常量而不是「按内容算」：选中一条与没选中、正文一行与十行，详情区一样高，
/// 切条目时卡片区与提示行都不会跳。
public enum ClipboardDetailStrip {

    /// 顶部分隔线高度
    public static let separatorHeight: CGFloat = 1
    /// 分隔线之下的内容高度（上下内边距 8 + 元信息行 13 + 间距 4 + 正文 4 行）
    public static let contentHeight: CGFloat = 101
    /// 详情区整块高度（含分隔线）
    public static var totalHeight: CGFloat { separatorHeight + contentHeight }
    /// 左右内边距
    public static let insetX: CGFloat = 10
    /// 上下内边距
    public static let insetY: CGFloat = 8
    /// 元信息行高
    public static let metaHeight: CGFloat = 13
    /// 元信息行与正文的间距
    public static let metaGap: CGFloat = 4
    /// 正文字号
    public static let bodyFontSize: CGFloat = 12.5
    /// 元信息字号
    public static let metaFontSize: CGFloat = 10.5
    /// 正文行距
    public static let lineSpacing: CGFloat = 2
    /// 无选中时的空态文案
    public static let emptyText = "选中一条查看详情"

    /// 正文可视高度（内容高 − 上下内边距 − 元信息行 − 间距），约等于 4 行 12.5pt 正文
    ///
    /// 用像素高度而不是「最大行数」：水平面裁切由滚动视图按像素完成，
    /// 「4 行」只是这一高度按当前字体度量出来的结果，写死行数反而会与字体度量脱钩。
    public static var bodyHeight: CGFloat { contentHeight - insetY * 2 - metaHeight - metaGap }

    /// 一条的详情展示内容
    public struct Content: Equatable, Sendable {
        /// 正文（文本为完整正文；图片为尺寸摘要）
        public let body: String
        /// 元信息：复制次数 · 类型 · 相对时间 · 来源 App
        public let meta: String
        /// 是否为空态（无选中）
        public let isEmpty: Bool

        public init(body: String, meta: String, isEmpty: Bool) {
            self.body = body
            self.meta = meta
            self.isEmpty = isEmpty
        }
    }

    /// 详情内容：无选中给空态文案，其余按条目类型取正文与元信息
    ///
    /// - Parameters:
    ///   - item: 当前选中条目（nil = 无选中）
    ///   - now: 相对时间的参照点（快照冻结时固定）
    public static func content(for item: ClipboardItem?, now: Date = SnapshotClock.now) -> Content {
        guard let item else {
            return Content(body: emptyText, meta: "", isEmpty: true)
        }
        return Content(body: bodyText(for: item), meta: metaText(for: item, now: now), isEmpty: false)
    }

    /// 正文：完整正文优先，缺失时退回摘要；图片条目给尺寸
    ///
    /// 不在这里截断字符串 —— 行数由视图按可见高度裁切并在内部滚动，提前截断会让用户再也看不到后半段。
    public static func bodyText(for item: ClipboardItem) -> String {
        if item.kind == .image {
            if let width = item.imageWidth, let height = item.imageHeight, width > 0, height > 0 {
                return "图片 \(width)×\(height)"
            }
            let preview = item.preview.trimmingCharacters(in: .whitespacesAndNewlines)
            return preview.isEmpty ? "图片" : preview
        }
        let full = item.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !full.isEmpty { return full }
        let preview = item.preview.trimmingCharacters(in: .whitespacesAndNewlines)
        return preview.isEmpty ? "（空内容）" : preview
    }

    /// 元信息：复制次数 · 类型 · 相对时间 · 来源 App（缺项自动跳过，不留空档）
    public static func metaText(for item: ClipboardItem, now: Date = SnapshotClock.now) -> String {
        var parts = ["复制 \(item.copyCount) 次", ClipboardItemKindLabel.label(for: item)]
        parts.append(ClipboardRelativeTime.string(from: item.createdAt, now: now))
        let source = item.sourceAppName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !source.isEmpty { parts.append(source) }
        return parts.joined(separator: " · ")
    }
}
