import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 排行屏的行文案与维度映射

// 从 TokenScreenContent+Ranking.swift 摘出（主文件贴近单文件 15 KiB 上限）：
// 这里只有纯映射与纯文案，不持有视图状态，主文件只保留装配与行高自适应。
// 文件名不带 `TokenScreenContent+` 前缀：它是行文案职责，不属于同族合计的屏内容族。
extension TokenRankingScreenView {

    /// 汇总块填值（总 tok / 缓存读 / 未缓存 / 输出 / 请求数）
    func updateSummary(_ totals: TokenDistroTotals) {
        let items: [(String, String)] = [
            ("总 tok", TokenFormatting.tokens(totals.totalTokens)),
            ("缓存读", TokenFormatting.tokens(totals.cacheRead)),
            ("未缓存", TokenFormatting.tokens(totals.uncached)),
            ("输出", TokenFormatting.tokens(totals.output)),
            ("请求数", TokenFormatting.grouped(totals.requestCount)),
        ]
        for (index, row) in summaryRows.enumerated() where index < items.count {
            row.update(title: items[index].0, value: items[index].1)
        }
    }

    /// 维度 → 分段下标（顺序 = TokenDistroDimension.all）
    static func index(for dimension: TokenDistroDimension) -> Int {
        TokenDistroDimension.all.firstIndex(of: dimension) ?? 0
    }

    static func dimension(forIndex index: Int) -> TokenDistroDimension {
        TokenDistroDimension.all.indices.contains(index) ? TokenDistroDimension.all[index] : .projects
    }

    /// 工具维度的段显隐：单源时藏起第一段（它只剩一行，没有信息量）
    ///
    /// 跨文件访问故为 internal（主类的 update 里调用）。
    func applyDimensionAvailability(showsTools: Bool) {
        guard let toolsRow = dimSegment.focusableRows.first else { return }
        toolsRow.isHidden = !showsTools
    }

    /// 第二行：项目 / 工具给「会话数 · 请求数」，模型给「provider · 请求数」
    static func metaText(row: TokenDistroRow) -> String {
        let requests = TokenFormatting.grouped(row.requestCount) + " 次请求"
        if row.sessionCount > 0 {
            return String(row.sessionCount) + " 会话 · " + requests
        }
        let provider = row.provider.isEmpty ? "未记录 provider" : "provider " + row.provider
        return provider + " · " + requests
    }
}
