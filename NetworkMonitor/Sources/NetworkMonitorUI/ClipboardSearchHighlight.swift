import Foundation

// MARK: - 搜索命中高亮（纯函数）

/// 搜索命中高亮 — 把「正文 + 查询」翻译成可绘制的命中区间，不持有任何 UI 状态
///
/// 三段口径：
/// 1. **多词 AND**：查询按空白切词，每个词都必须在正文里出现，否则整条不命中
///    （只高亮一半会让用户以为查询被截断了）；
/// 2. **大小写不敏感 + 全量定位**：每个词按字符偏移全量扫描并允许重叠
///    （`"aaa"` 里查 `"aa"` 两个位置都算），重叠段由合并步骤收成一段；
/// 3. **合并 + 上限**：排序后把相交 / 相邻段并成一段，最后截到 `maxRanges`（32）段，
///    防止超长正文 + 单字符查询画出上千段让绘制失控。
///
/// **断行插零宽空格是本模块唯一的坑**：卡片正文绘制前会走
/// `ClipboardCardTextStyle.breakable`，在断点字符后埋零宽空格（U+200B），
/// 显示串的字符偏移与原始正文不再一一对应 —— 直接在显示串上搜 `"ab"` 会因为中间夹了
/// 零宽空格而搜不到。因此对外分两个入口：
/// - `ranges(in:query:)`：原始正文口径；
/// - `displayRanges(inDisplay:query:)`：显示文本口径 —— 先把显示串里的零宽空格剥掉还原出
///   可搜索正文，命中后再按「偏移 → 显示索引」的映射贴回显示串。
///   断行只会**追加**零宽空格、不改动原有字符，故映射是稳定的。
public enum ClipboardSearchHighlight {

    /// 高亮段上限（超过即丢弃靠后的段，只保留前 32 处）
    public static let maxRanges = 32

    // MARK: 对外入口

    /// 原始正文口径的命中区间（未断行插入零宽空格前）
    public static func ranges(in text: String, query: String) -> [Range<String.Index>] {
        offsetRanges(in: text, query: query).map { indexRange($0, in: text) }
    }

    /// 显示文本口径的命中区间（已断行、含零宽空格的 `ClipboardCardTextStyle.breakable` 输出）
    ///
    /// 返回的区间直接落在传入的 `displayText` 上，可交给 `NSMutableAttributedString` 上色。
    public static func displayRanges(inDisplay displayText: String,
                                     query: String) -> [Range<String.Index>] {
        let probe = DisplayProbe(displayText)
        return offsetRanges(in: probe.searchableText, query: query).compactMap(probe.displayRange(for:))
    }

    /// 命中的字符偏移区间（半开区间；已排序、已合并、已按上限截断）
    ///
    /// 偏移口径 = 从 `text.startIndex` 起的字符数（按 Character 计，与 String 索引一致）。
    public static func offsetRanges(in text: String, query: String) -> [Range<Int>] {
        guard !text.isEmpty else { return [] }
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !terms.isEmpty else { return [] }
        var collected: [Range<Int>] = []
        for term in terms {
            let hits = matches(of: term, in: text)
            // 多词 AND：任一词不出现即整条不高亮
            guard !hits.isEmpty else { return [] }
            collected.append(contentsOf: hits)
        }
        return Array(merge(collected).prefix(maxRanges))
    }

    // MARK: 定位

    /// 单个词的全部命中偏移（允许重叠：每次只前进一个字符再搜）
    private static func matches(of term: String, in text: String) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let hit = text.range(of: term, options: [.caseInsensitive],
                                   range: searchStart..<text.endIndex) {
            result.append(text.distance(from: text.startIndex, to: hit.lowerBound)
                          ..< text.distance(from: text.startIndex, to: hit.upperBound))
            searchStart = text.index(after: hit.lowerBound)
        }
        return result
    }

    /// 相交 / 相邻段合并（`[0,2)` 与 `[2,4)` 并成 `[0,4)`，避免画出零宽缝隙）
    private static func merge(_ ranges: [Range<Int>]) -> [Range<Int>] {
        let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [Range<Int>] = []
        for range in sorted {
            guard let last = merged.last else {
                merged.append(range)
                continue
            }
            if range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    /// 偏移区间 → 字符串索引区间
    private static func indexRange(_ offsets: Range<Int>, in text: String) -> Range<String.Index> {
        text.index(text.startIndex, offsetBy: offsets.lowerBound)
            ..< text.index(text.startIndex, offsetBy: offsets.upperBound)
    }

    // MARK: 零宽空格映射

    /// 显示文本探针：剥掉零宽空格后的可搜索正文 + 「正文偏移 → 显示索引」映射
    private struct DisplayProbe {
        /// 剥掉零宽空格后的正文（搜索与原始正文同一口径）
        let searchableText: String
        /// `searchableText` 第 i 个字符在显示文本里的起点；末尾多存一个 endIndex 作右开边界
        let displayStarts: [String.Index]

        init(_ displayText: String) {
            var searchable = ""
            var starts: [String.Index] = []
            var index = displayText.startIndex
            while index < displayText.endIndex {
                let next = displayText.index(after: index)
                // 零宽空格只是断行机会：既不进搜索正文，也不占映射位
                if displayText[index] != Character(ClipboardCardTextStyle.zeroWidthSpace) {
                    searchable.append(displayText[index])
                    starts.append(index)
                }
                index = next
            }
            searchableText = searchable
            displayStarts = starts + [displayText.endIndex]
        }

        /// 正文偏移区间 → 显示文本索引区间
        ///
        /// 命中末尾若紧跟零宽空格，边界停在下一字符的起点（零宽空格本身不可见，不影响观感）；
        /// 命中落在正文末尾时右边界取显示文本的 endIndex，把尾部零宽空格一并纳入。
        func displayRange(for offsets: Range<Int>) -> Range<String.Index>? {
            guard offsets.lowerBound >= 0, offsets.upperBound <= displayStarts.count - 1,
                  offsets.lowerBound < offsets.upperBound else { return nil }
            return displayStarts[offsets.lowerBound]..<displayStarts[offsets.upperBound]
        }
    }
}
