import Foundation

// MARK: - 网络页实时速率区（Hero）的宽度分配

/// 网络页 Hero 的排布口径 —— 与 AppKit 无关，TestRunner 可直接断言
///
/// 存在理由（实测）：改前是「下行左列 / 上行右列」两列并排，两条 MenuPanelSparklineView
/// 各写死 84pt 宽，两列之间靠一个弹性 spacer 撑开 —— 面板内容宽 296pt 时
/// 折线只占最左 / 最右各 84pt，中间空出约 128pt。用户口径：
/// 「网络这边的实时监控线条太短了，然后中间存在大量的空白」。
///
/// 改后下行 / 上行各占一整行：左侧文本列（分区标签 + 数值 + 单位）固定宽，折线吃满剩余。
/// 文本列固定宽而非按内容自适应，是因为数值每秒刷新（999 KB/s ↔ 1.2 MB/s）宽度会变，
/// 自适应会让折线左边界每秒跳一次。
public enum NetworkHeroLayout {

    /// 文本列与折线之间的间距
    public static let gap: CGFloat = 8

    /// 文本列固定宽度（pt）
    ///
    /// 按最坏情况量出来的（AppKit size(withAttributes:) 实测）：数值 24pt 等宽 5 字符
    /// "999.9" = 69.1pt + 2pt 间距 + 单位 "MB/s" 11pt 半粗 27.2pt = 98.3pt；
    /// 分区标签「实时下行」11pt 粗体 43.7pt 更窄，不构成约束。取 106pt 够放最宽数值，
    /// 剩下的宽度全让给折线。
    public static let textColumnWidth: CGFloat = 106

    /// 折线高度（pt）
    ///
    /// 两行竖排后总高比改前的两列并排高，必须比原来的 20pt 矮一档才不顶出 520pt 外框：
    /// 改前网络页面板需求高 511pt，两行化后按 20pt 算是 524pt（超上限 4pt，会出滚动条）；
    /// 16pt 让回 8pt。16pt 与系统页迷你折线（12pt）同量级，形状仍可读。
    public static let sparklineHeight: CGFloat = 16

    /// 折线最小宽度：低于这个值 60 个采样点挤成一条实线，等于没画出趋势
    public static let minimumSparklineWidth: CGFloat = 80

    /// 一次排布的结果
    public struct Metrics: Equatable {
        /// 文本列宽度
        public let textColumnWidth: CGFloat
        /// 折线实得宽度
        public let sparklineWidth: CGFloat

        public init(textColumnWidth: CGFloat, sparklineWidth: CGFloat) {
            self.textColumnWidth = textColumnWidth
            self.sparklineWidth = sparklineWidth
        }
    }

    /// 折线宽度 = 内容宽 − 文本列 − 间距，并钳到最小宽度
    ///
    /// 面板窄到放不下时宁可让折线保底宽度，也不让它退化成一条实线。
    public static func sparklineWidth(contentWidth: CGFloat,
                                      columnWidth: CGFloat = NetworkHeroLayout.textColumnWidth,
                                      gap: CGFloat = NetworkHeroLayout.gap) -> CGFloat {
        max(minimumSparklineWidth, contentWidth - columnWidth - gap)
    }

    /// 一次算出该页的排布
    public static func metrics(contentWidth: CGFloat,
                               columnWidth: CGFloat = NetworkHeroLayout.textColumnWidth) -> Metrics {
        Metrics(textColumnWidth: columnWidth,
                sparklineWidth: sparklineWidth(contentWidth: contentWidth, columnWidth: columnWidth))
    }
}
