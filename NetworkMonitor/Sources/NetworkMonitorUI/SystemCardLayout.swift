import Foundation

// MARK: - 系统页首屏（五卡 + 状态带）的纯口径

/// 系统页首屏的排布口径 —— 与 AppKit 无关，TestRunner 可直接断言
///
/// 抽出理由：改造前卡内外位置由 Auto Layout（NSStackView + 约束）算出，测试够不着；
/// 改成「整卡一个视图、一次 draw 画完」后位置必须自己算，把「怎么算」收敛到这里，
/// 视图只负责按算好的矩形画，卡内不再有视图树。
public enum SystemCardLayout {

    // MARK: 卡头一行

    /// 卡头一行的横向位置（全部相对「卡内左边界」，即已扣掉左右内边距）
    public struct Head: Equatable {
        /// 标题左边界
        public let titleX: CGFloat
        /// 卡头附属件（图例 / 徽标 / 微条）左边界
        public let accessoryX: CGFloat
        /// 右侧说明的右对齐起点（= 右边界 − 宽度）
        public let captionX: CGFloat
        /// 右侧说明实得宽度（0 = 不画）
        public let captionWidth: CGFloat
        /// 最右端块（「›」/「全部 ›」按钮）左边界
        public let trailingX: CGFloat

        public init(titleX: CGFloat, accessoryX: CGFloat,
                    captionX: CGFloat, captionWidth: CGFloat, trailingX: CGFloat) {
            self.titleX = titleX
            self.accessoryX = accessoryX
            self.captionX = captionX
            self.captionWidth = captionWidth
            self.trailingX = trailingX
        }
    }

    /// 卡头一行位置
    ///
    /// 排布顺序与改造前的 NSStackView 一致：标题贴左 → 附属件紧跟（间距 gap）→
    /// 弹性占位 → 右侧说明右对齐（间距 gap）→ 最右端块贴右。
    /// 说明放不下时先让位（宁可省略号，也不压住标题与附属件）。
    /// - Parameters:
    ///   - width: 卡内可用宽（已扣左右内边距）
    ///   - titleWidth: 标题实测宽
    ///   - accessoryWidth: 附属件实测宽（0 = 无）
    ///   - captionWidth: 右侧说明实测宽（0 = 无）
    ///   - trailingWidth: 最右端块实测宽（0 = 无）
    ///   - gap: 相邻两件之间的间距
    public static func head(width: CGFloat,
                            titleWidth: CGFloat,
                            accessoryWidth: CGFloat,
                            captionWidth: CGFloat,
                            trailingWidth: CGFloat,
                            gap: CGFloat) -> Head {
        let trailingX = max(width - trailingWidth, 0)
        let accessoryX = titleWidth + (accessoryWidth > 0 ? gap : 0)
        let leftEdge = accessoryWidth > 0 ? accessoryX + accessoryWidth : titleWidth
        let rightEdge = trailingWidth > 0 ? trailingX - gap : max(width, 0)
        let captionFit = max(rightEdge - leftEdge - (captionWidth > 0 ? gap : 0), 0)
        let caption = min(max(captionWidth, 0), captionFit)
        return Head(titleX: 0,
                    accessoryX: accessoryX,
                    captionX: rightEdge - caption,
                    captionWidth: caption,
                    trailingX: trailingX)
    }

    // MARK: 卡片高度与内容区

    /// 卡片高度 = 上下内边距 + 卡头 + 卡头间距 + 内容高
    ///
    /// 内容高为 0 时仍然留卡头间距：改造前那一行是 NSStackView 的 spacing（无内容的卡
    /// 也照算），磁盘卡（只有卡头一行，高 26pt）就是 4 + 14 + 4 + 0 + 4。
    public static func cardHeight(contentHeight: CGFloat,
                                  headHeight: CGFloat,
                                  headSpacing: CGFloat,
                                  paddingY: CGFloat) -> CGFloat {
        paddingY * 2 + headHeight + headSpacing + max(contentHeight, 0)
    }

    /// 内容区在卡片内的矩形（flipped 坐标，自上而下）
    public static func contentRect(width: CGFloat,
                                   contentHeight: CGFloat,
                                   headHeight: CGFloat,
                                   headSpacing: CGFloat,
                                   paddingX: CGFloat,
                                   paddingY: CGFloat) -> CGRect {
        CGRect(x: paddingX,
               y: paddingY + headHeight + headSpacing,
               width: max(width - paddingX * 2, 0),
               height: max(contentHeight, 0))
    }

    // MARK: 横向读数条（图例 / 键值对 / 状态带分组）

    /// 读数条的一段：宽（横向占用）+ 高（决定整条行高）
    public struct ReadoutPiece: Equatable {
        public let width: CGFloat
        public let height: CGFloat

        public init(width: CGFloat, height: CGFloat) {
            self.width = width
            self.height = height
        }
    }

    /// 读数条各段起点（相对左边界，按组展开后的顺序）
    ///
    /// 组内间距 innerGap、组间间距 groupGap —— 与改造前的嵌套 NSStackView 一致
    /// （图例两枚之间 8pt、色块与数值之间 2pt；状态带三组之间 8pt、组内 3pt）。
    public static func readoutOffsets(groups: [[ReadoutPiece]],
                                      innerGap: CGFloat,
                                      groupGap: CGFloat) -> [CGFloat] {
        var offsets: [CGFloat] = []
        offsets.reserveCapacity(groups.reduce(0) { $0 + $1.count })
        var cursor: CGFloat = 0
        for (groupIndex, group) in groups.enumerated() {
            if groupIndex > 0 { cursor += groupGap }
            for (index, piece) in group.enumerated() {
                if index > 0 { cursor += innerGap }
                offsets.append(cursor)
                cursor += piece.width
            }
        }
        return offsets
    }

    /// 读数条总宽（最后一段之后不留间距）
    public static func readoutWidth(groups: [[ReadoutPiece]],
                                    innerGap: CGFloat,
                                    groupGap: CGFloat) -> CGFloat {
        var width: CGFloat = 0
        for (groupIndex, group) in groups.enumerated() {
            if groupIndex > 0 { width += groupGap }
            for (index, piece) in group.enumerated() {
                if index > 0 { width += innerGap }
                width += piece.width
            }
        }
        return width
    }

    /// 读数条行高（各段最高者）
    public static func readoutHeight(groups: [[ReadoutPiece]]) -> CGFloat {
        groups.flatMap { $0 }.map { $0.height }.max() ?? 0
    }

    // MARK: 堆叠条的段宽

    /// 分段宽度 —— 按 total 归一化，越界段先夹到 0…1
    ///
    /// 与改造前 SystemStackedBarView 的算法逐字一致（段宽 = 整条宽 × 占比，
    /// 各段依次向右累加；超出整条宽的部分由圆角裁切吃掉），因此换了绘制入口也不改像素。
    public static func segmentWidths(values: [Double], total: Double, width: CGFloat) -> [CGFloat] {
        guard total.isFinite, total > 0 else { return values.map { _ in 0 } }
        return values.map { value in
            guard value.isFinite, value > 0 else { return 0 }
            let ratio = min(1, max(0, value / total))
            return width * CGFloat(ratio)
        }
    }

    // MARK: 负载纵轴

    /// 负载三线纵轴上限：max(核数 × 1.2, 峰值 × 1.15, 1)
    ///
    /// 下限用核数保证「低负载时不要把噪声放大成满画布」，上限用峰值让三条线用满高度。
    /// 负载是就绪队列长度（可以远超核数），所以量程不是固定 0–100%。
    public static func loadAxisMaximum(coreCount: Int, peak: Double) -> Double {
        let byCores = Double(max(coreCount, 0)) * 1.2
        let byPeak = (peak.isFinite ? max(peak, 0) : 0) * 1.15
        return max(byCores, byPeak, 1)
    }

    // MARK: CPU 用户态 / 系统态取整

    /// 用户态 / 系统态的显示百分比 —— 两段取整后必须凑得出总量
    ///
    /// 各段独立四舍五入会凑不出总量（total 29%、sys 14.5% → 用户 15% + 系统 15% = 30% ≠ 29%），
    /// 所以用户态按「总量取整 − 系统态取整」反算，两枚数字与卡内大号读数恒自洽。
    public static func usageSplitPercents(total: Double, system: Double) -> (user: Int, system: Int) {
        let totalPercent = Int((clamped(total) * 100).rounded())
        let systemPercent = min(totalPercent, Int((clamped(system) * 100).rounded()))
        return (user: max(0, totalPercent - systemPercent), system: systemPercent)
    }

    /// 0…1 夹紧（非有限值归 0）
    private static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }
}
