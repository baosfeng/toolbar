import AppKit
import NetworkMonitorUI

// MARK: - 横向读数条（图例 / 键值对 / 状态带分组）

/// 读数条里的一段 —— 值类型，只描述「这一段是什么」
@MainActor
package enum DrawnReadoutPiece {
    /// 一段文字（自带字体与颜色）
    case text(DrawnTextRun)
    /// 圆角色块（图例色点 / 线形色块 / 压力徽标）
    case swatch(color: NSColor, width: CGFloat, height: CGFloat, radius: CGFloat)
    /// 圆点（Wi-Fi 档位这类需要 1pt 内边才脱离浅底的点）
    case dot(color: NSColor, size: CGFloat, ringColor: NSColor?)
    /// 进度微条（繁忙度 / 占比）
    case track(fraction: Double, width: CGFloat, height: CGFloat,
               track: NSColor, fill: NSColor)
    /// 进度环（电量这类小环）
    case ring(fraction: Double, diameter: CGFloat, lineWidth: CGFloat,
              color: NSColor, track: NSColor)

    /// 这一段占的宽（文字段用 0.5pt 网格的排版宽，与 AppKit 标签对齐矩形同源）
    var width: CGFloat {
        switch self {
        case .text(let run): return run.layoutWidth
        case .swatch(_, let width, _, _): return width
        case .dot(_, let size, _): return size
        case .track(_, let width, _, _, _): return width
        case .ring(_, let diameter, _, _, _): return diameter
        }
    }

    /// 这一段占的高（决定整条行高；文字段用行框高，与标签 frame 同源）
    var height: CGFloat {
        switch self {
        case .text(let run): return run.labelHeight
        case .swatch(_, _, let height, _): return height
        case .dot(_, let size, _): return size
        case .track(_, _, let height, _, _): return height
        case .ring(_, let diameter, _, _, _): return diameter
        }
    }

    /// 读屏文案（图形段不读，只有文字段出声）
    var accessibilityText: String? {
        if case .text(let run) = self { return run.string }
        return nil
    }

    /// 按「左边界 + 行中心」画自己
    func draw(at x: CGFloat, centerY: CGFloat) {
        switch self {
        case .text(let run):
            run.draw(topIn: CGRect(x: x, y: centerY - run.labelHeight / 2,
                                   width: run.layoutWidth, height: run.labelHeight))
        case .swatch(let color, let width, let height, let radius):
            DrawnInk.fill(CGRect(x: x, y: centerY - height / 2, width: width, height: height),
                          radius: radius, color: color)
        case .dot(let color, let size, let ringColor):
            DrawnInk.circle(in: CGRect(x: x, y: centerY - size / 2, width: size, height: size),
                            fill: color, stroke: ringColor)
        case .track(let fraction, let width, let height, let track, let fill):
            DrawnInk.progressBar(in: CGRect(x: x, y: centerY - height / 2,
                                           width: width, height: height),
                                 progress: fraction, track: track, fill: fill)
        case .ring(let fraction, let diameter, let lineWidth, let color, let track):
            DrawnInk.ring(in: CGRect(x: x, y: centerY - diameter / 2,
                                     width: diameter, height: diameter),
                          fraction: fraction, lineWidth: lineWidth, color: color, track: track)
        }
    }
}

/// 横向读数条 —— 若干组「色块 / 圆点 / 微条 / 环 / 文字」横排，宽度自量、垂直居中
///
/// 面板里所有「图例」「键值对」「状态带分组」长得都一样：几段等距元素居中排一行。
/// 改造前每一处都是 NSStackView + N 个视图（系统页三类图例 + 状态带三组 = 40 多个视图），
/// 现在调用方只描述「这一段是什么」，位置由 SystemCardLayout 的读数条口径算，
/// 一次 draw 画完整条，一个视图都不用建。
///
/// 分两级间距的理由与改造前一致：同一枚图例里「色块—数值」贴得近（2pt），
/// 相邻两枚之间拉开（8pt）；状态带同理（组内 3pt、组间 8pt）。
@MainActor
package struct DrawnReadoutRun {

    /// 各组（组内从左到右）
    var groups: [[DrawnReadoutPiece]] = []
    /// 组内间距
    var innerGap: CGFloat = 3
    /// 组间间距
    var groupGap: CGFloat = 8

    package init(groups: [[DrawnReadoutPiece]] = [], innerGap: CGFloat = 3, groupGap: CGFloat = 8) {
        self.groups = groups
        self.innerGap = innerGap
        self.groupGap = groupGap
    }

    /// 几何（宽度分配的唯一来源，绘制与量宽共用同一份）
    private var layoutGroups: [[SystemCardLayout.ReadoutPiece]] {
        groups.map { group in
            group.map { SystemCardLayout.ReadoutPiece(width: $0.width, height: $0.height) }
        }
    }

    /// 整条宽
    package var width: CGFloat {
        SystemCardLayout.readoutWidth(groups: layoutGroups, innerGap: innerGap, groupGap: groupGap)
    }

    /// 整条行高
    var height: CGFloat { SystemCardLayout.readoutHeight(groups: layoutGroups) }

    /// 读屏文案（文字段按顺序拼接）
    package var accessibilityText: String {
        groups.flatMap { $0 }.compactMap { $0.accessibilityText }.joined(separator: " ")
    }

    /// 从左边界 x 起、以 centerY 为行中心画完整条
    package func draw(at x: CGFloat, centerY: CGFloat) {
        let offsets = SystemCardLayout.readoutOffsets(groups: layoutGroups,
                                                      innerGap: innerGap,
                                                      groupGap: groupGap)
        var cursor = 0
        for group in groups {
            for piece in group {
                guard cursor < offsets.count else { return }
                piece.draw(at: x + offsets[cursor], centerY: centerY)
                cursor += 1
            }
        }
    }
}
