import Foundation

// MARK: - 模糊搜索

/// 模糊搜索打分与排序（纯函数，无状态）
///
/// 匹配目标：条目摘要 preview + 来源 App 名（摘要已折叠换行并截断，见 ClipboardPreview）。
/// 打分分档：完全相同 > 前缀 > 子串（越靠前越高）> 顺序子序列（跳字）。
/// 同分条目严格保持入参顺序（入参已按「收藏优先 + 时间倒序」排好），保证排序稳定可预期。
///
/// - Note: 原「乱序字符齐全」档（`Set(query).isSubset(of: Set(target))`，基准分 100）已删除，
///   理由：该档只校验字符集合包含、与出现顺序无关，而中文常用字集合极小且长文本覆盖率极高，
///   短查询（如「的一」「ab」）会命中几乎全部长文本 —— 这是无法靠调分或阈值消除的结构性噪音
///   （基准分降到 0 就等于该档不存在），且用户几乎不会以乱序输入为检索意图。
///   取舍：宁可漏召回，也不要让搜索结果被假命中淹没；确需容错时可改用顺序子序列/子串档。
public enum ClipboardFuzzySearch {

    /// 单条打分
    /// - Parameters:
    ///   - query: 查询串（空串 / 全空白不参与打分，返回 0）
    ///   - target: 被打分文本
    /// - Returns: 分值，0 表示不匹配
    public static func score(query: String, target: String) -> Int {
        let q = normalize(query)
        guard !q.isEmpty else { return 0 }
        let t = normalize(target)
        guard !t.isEmpty else { return 0 }

        let base: Int
        if t == q {
            base = 1000
        } else if t.hasPrefix(q) {
            base = 800
        } else if let range = t.range(of: q) {
            let offset = t.distance(from: t.startIndex, to: range.lowerBound)
            base = 600 - min(offset, 100)
        } else if let gaps = subsequenceGaps(q, in: t) {
            base = 300 - min(gaps, 200)
        } else {
            // 「乱序字符齐全」档已按上文 Note 删除：不再返回 100 分，直接判为不匹配
            return 0
        }
        // 目标越短越接近查询本身，同档内做长度微调
        return base + max(0, 50 - t.count)
    }

    /// 排序：过滤不匹配项后按分值降序，同分保持入参顺序
    /// - Parameter query: 空串 / 全空白时按入参既有排序返回完整列表
    public static func rank(_ query: String, items: [ClipboardItem]) -> [ClipboardItem] {
        guard !normalize(query).isEmpty else { return items }
        let scored: [(score: Int, index: Int, item: ClipboardItem)] = items.enumerated().map { pair in
            (score(query: query, target: searchTarget(for: pair.element)), pair.offset, pair.element)
        }
        return scored
            .filter { $0.score > 0 }
            .sorted { $0.score == $1.score ? $0.index < $1.index : $0.score > $1.score }
            .map(\.item)
    }

    /// 条目的搜索目标文本（摘要 + 来源 App 名）
    public static func searchTarget(for item: ClipboardItem) -> String {
        var parts = [item.preview]
        if let app = item.sourceAppName, !app.isEmpty { parts.append(app) }
        return parts.joined(separator: " ")
    }

    // MARK: - 内部实现

    /// 归一化：小写 + 去首尾空白（中文不受小写影响，直接参与子串匹配）
    private static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// 顺序子序列匹配，返回跳过的字符总数；不匹配返回 nil
    private static func subsequenceGaps(_ query: String, in target: String) -> Int? {
        var gaps = 0
        var cursor = target.startIndex
        for character in query {
            guard let found = target[cursor...].firstIndex(of: character) else { return nil }
            gaps += target.distance(from: cursor, to: found)
            cursor = target.index(after: found)
        }
        return gaps
    }
}
