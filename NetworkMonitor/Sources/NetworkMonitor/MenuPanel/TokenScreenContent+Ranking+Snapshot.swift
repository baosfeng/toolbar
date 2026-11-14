import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 排行屏快照自证接口（仅 DEBUG）

// 从 TokenScreenContent+Ranking.swift 拆出：主文件接入自绘列表后越过单文件体积门禁。
// 这些接口只在 NM_SNAPSHOT_DIR 取证时被调用，发布构建完全不包含。

#if DEBUG
extension TokenRankingScreenView {


    /// 快照自证：排行行的一份规格 + 度量（行不是视图，逐行只导数据与宽度）
    struct RankingRowProbe {
        let index: Int
        let title: String
        let value: String
        let secondary: String
        let detail: String
        let tip: String
        let titleAvailable: CGFloat
        let titleNeeded: CGFloat
        let titleHeight: CGFloat
        let valueAvailable: CGFloat
        let valueNeeded: CGFloat
        let rowWidth: CGFloat
        let rowHeight: CGFloat
    }

    /// 快照自证：当前列表里的全部可见行
    func rowProbesForSnapshot() -> [RankingRowProbe] {
        layoutSubtreeIfNeeded()
        return rowList.rows.enumerated().compactMap { index, row in
            guard let metric = rowList.stackedRowMetricsForSnapshot(index) else { return nil }
            return RankingRowProbe(index: index,
                                   title: row.title,
                                   value: row.value,
                                   secondary: row.secondary,
                                   detail: row.detail,
                                   tip: rowList.rowTipForSnapshot(index),
                                   titleAvailable: metric.titleAvailable,
                                   titleNeeded: metric.titleNeeded,
                                   titleHeight: metric.titleHeight,
                                   valueAvailable: metric.valueAvailable,
                                   valueNeeded: metric.valueNeeded,
                                   rowWidth: metric.rowWidth,
                                   rowHeight: metric.rowHeight)
        }
    }

    /// 快照自证：顶部分段 / 占比条
    var segmentForSnapshot: TokenSegmentedControl { dimSegment }
    var barForSnapshot: TokenStackBarView { bar }
    /// 快照自证：行列表本身（量宽度 / 行高用）
    var rowListForSnapshot: DrawnRowList { rowList }

    /// 快照自证：可见行数 / 实测行高 / 剩余留白（台账「行高 / 内容占比 / 空白」用）
    func rowMetricsForSnapshot() -> (visible: Int, rowHeight: CGFloat, blank: CGFloat) {
        layoutSubtreeIfNeeded()
        let visible = rowList.rows.count
        let height = visible > 0 ? rowList.rowHeight : 0
        return (visible, height, spacer.bounds.height)
    }

    /// 快照自证：卡内各块实测高度（行高自适应的输入，用来查「谁把空间吸走了」）
    func cardPartsForSnapshot() -> String {
        layoutSubtreeIfNeeded()
        let parts = card.body.arrangedSubviews.filter { !$0.isHidden }.map { view -> String in
            let name: String
            if view === rowList { name = "rows" }
            else if view === spacer { name = "blank" }
            else if view === summaryGrid { name = "summary" }
            else if view === noteView { name = "note" }
            else if view === head { name = "head" }
            else if view === bar { name = "bar" }
            else { name = "dim" }
            return name + "=" + String(format: "%.1f", view.frame.height)
        }
        return "body=" + String(format: "%.1f", card.body.bounds.height) + " " + parts.joined(separator: " ")
    }
}
#endif
