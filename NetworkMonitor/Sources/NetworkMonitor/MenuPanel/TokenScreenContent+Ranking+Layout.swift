import AppKit
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 排行屏行高自适应（从 TokenScreenContent+Ranking.swift 拆出：单文件体积门禁）

/// 行高自适应是独立的变更理由：改它只跟「一屏能放几行、余量给谁」有关，
/// 与维度切换 / 占比条 / 口径文案那套数据搬运无关。
///
/// `layout()` 这个 override 只能留在主类（Swift 不允许在扩展里 override），
/// 它只负责调这里；算法本身在这个文件。
extension TokenRankingScreenView {

    /// 按「可用高度 ÷ 可见行数」定行高（夹在 min…max），封顶后剩下的高度交给留白 spacer
    func updateRowHeights() {
        guard !isMeasuring, card.bounds.height > 0 else { return }
        let visible = rowList.rows.count
        guard visible > 0 else { return }
        isMeasuring = true
        defer { isMeasuring = false }
        let body = card.body
        // 注意要排除 spacer 自己：把它的当前高度算进 used 会形成自反馈（行高被压在 35pt 不动）
        let siblings = body.arrangedSubviews.filter {
            $0 !== rowList && $0 !== spacer && !$0.isHidden
        }
        // 可见段之间的间距：兄弟块 N 个 + 行列表 + spacer 自身
        let gaps = CGFloat(siblings.count + 1) * body.spacing
        let used = siblings.reduce(CGFloat(0)) { $0 + $1.frame.height } + gaps
        let available = max(0, body.bounds.height - used)
        // 行间距从可用高度里先扣，再均分给行——与改造前 fillEqually 的行高口径一致
        // （否则 2 行时行高会比旧版多 1pt，行高台账对不上）
        let spacing = rowList.rowSpacing
        let usable = max(0, available - spacing * CGFloat(max(visible - 1, 0)))
        let rowHeight = min(Self.maxRowHeight,
                            max(Self.minRowHeight, usable / CGFloat(visible)))
        if abs(rowList.rowHeight - rowHeight) > 0.5 {
            rowList.rowHeight = rowHeight
        }
        let total = DrawnRowLayout.contentHeight(rowCount: visible,
                                                 rowHeight: rowHeight,
                                                 rowSpacing: rowList.rowSpacing)
        if let rowsHeight, abs(rowsHeight.constant - total) > 0.5 {
            rowsHeight.constant = total
        }
        if abs((spacerHeight?.constant ?? -1) - max(0, available - total)) > 0.5 {
            spacerHeight?.constant = max(0, available - total)
        }
    }
}
