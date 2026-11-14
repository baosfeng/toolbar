import AppKit

// MARK: - 卡片几何

/// 卡片内部几何 — 由卡片主视图与内容层共用，避免第二套 frame 换算
///
/// 口径固定（设计规格）：卡片 176×198、内边距 10、meta 行 16、正文与 meta 间距 6、圆角 12。
/// 主线程隔离：尺寸令牌来自 `ClipboardCardView`（AppKit 视图类型，`@MainActor`）。
@MainActor
enum ClipboardCardLayout {

    /// 内容区（四边内缩 padding）
    static func contentRect(in bounds: NSRect) -> NSRect {
        bounds.insetBy(dx: ClipboardCardView.padding, dy: ClipboardCardView.padding)
    }

    /// 正文区（内容区去掉底部 meta 行）
    static func bodyRect(in bounds: NSRect) -> NSRect {
        let content = contentRect(in: bounds)
        return NSRect(x: content.minX, y: content.minY, width: content.width,
                      height: max(0, content.height - ClipboardCardView.metaHeight - ClipboardCardView.bodyGap))
    }

    /// meta 行的纵向起点（翻转坐标系下为 meta 行顶边）
    static func metaRowY(in bounds: NSRect) -> CGFloat {
        contentRect(in: bounds).maxY - ClipboardCardView.metaHeight
    }

    /// 收藏星位置：类型图标 + ⌘N 之后（布局随序号宽度浮动，不动卡片尺寸）
    static func starRect(in bounds: NSRect, number: Int?) -> NSRect {
        let content = contentRect(in: bounds)
        let rowY = metaRowY(in: bounds)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: ClipboardCardView.metaFontSize, weight: .regular)
        ]
        var leftX = content.minX + ClipboardCardView.typeIconSize + ClipboardCardView.metaGap
        if let number, (1...9).contains(number) {
            leftX += ("⌘\(number)" as NSString).size(withAttributes: attributes).width + ClipboardCardView.metaGap
        }
        return NSRect(x: leftX, y: rowY + (ClipboardCardView.metaHeight - ClipboardCardView.starSize) / 2,
                      width: ClipboardCardView.starSize, height: ClipboardCardView.starSize)
    }
}
