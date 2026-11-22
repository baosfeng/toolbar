import Foundation

// MARK: - 排行屏「按工具」维度（Core 纯函数，视图只搬运）

/// 按工具 = 按来源：每个有数据的来源一行，跟随当前范围
///
/// 为什么放在 Core：占比分母、行序、悬停文案都是口径；写在视图里 TestRunner 就够不着。
/// 每个来源的数值取自该来源收窄后的快照（与「按项目 / 按模型」同一个窗口同一种合计），
/// 所以切范围时三段的数值同进同退。
package enum TokenToolRanking {

    /// 有数据的来源（会话数 > 0 或用量非零），按当前窗口用量降序
    package static func rows(_ snapshot: HarnessUsageSnapshot,
                             range: TokenRange) -> [TokenDistroRow] {
        let window = range.window
        let total = (snapshot.windowProjectTotals[window] ?? .zero).totalTokens
        let entries = TokenSourceID.allCases.compactMap { id -> (TokenSourceID, HarnessTokenUsage, Int)? in
            guard let entry = snapshot.bySource[id],
                  entry.sessionCount > 0 || !entry.usage.isZero else { return nil }
            // 该来源在当前窗口的合计：用项目合计这一项（窗口全量，不是 TopN 求和）
            let usage = snapshot.scoped(to: id).windowProjectTotals[window] ?? .zero
            guard usage.totalTokens > 0 || usage.requestCount > 0 || entry.sessionCount > 0 else { return nil }
            return (id, usage, entry.sessionCount)
        }.sorted { left, right in
            if left.1.totalTokens != right.1.totalTokens { return left.1.totalTokens > right.1.totalTokens }
            return left.0.rawValue < right.0.rawValue
        }
        return entries.enumerated().map { index, item in
            let (id, usage, sessions) = item
            let tokens = usage.totalTokens
            let share = total > 0 ? Double(tokens) / Double(total) : 0
            let amount = TokenFormatting.tokens(tokens)
            return TokenDistroRow(rank: index + 1,
                                  name: id.displayName,
                                  provider: "",
                                  sub: String(sessions) + " 会话 · 占 " + TokenFormatting.percent(share),
                                  amount: amount,
                                  share: share,
                                  requestCount: usage.requestCount,
                                  sessionCount: sessions,
                                  colorIndex: index,
                                  tip: id.displayName + "\n" + String(sessions) + " 会话 · "
                                      + TokenFormatting.grouped(usage.requestCount) + " 次请求 · 占 "
                                      + TokenFormatting.percent(share) + "（" + range.title + "）")
        }
    }

    /// 汇总块的合计（与占比分母同一份数据）
    package static func totals(_ snapshot: HarnessUsageSnapshot, range: TokenRange) -> TokenDistroTotals {
        TokenDistroTotals(usage: snapshot.windowProjectTotals[range.window] ?? .zero)
    }

    /// 口径说明（底部说明卡）
    package static func note(range: TokenRange) -> String {
        "口径：按工具一行一个来源，数值与占比跟随当前范围（" + range.title
            + "），分母是各来源合计；在设置页关掉的来源不进这一段，它已有的索引数据保留、重新打开即恢复。"
    }
}
