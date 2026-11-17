import Foundation
import NetworkMonitorUI

// MARK: - 搜索命中高亮（纯函数）

/// 搜索高亮的守门测试
///
/// 钉住六件事：单命中 / 多命中 / 大小写不敏感 / 多词 AND / 重叠合并 / 上限截断，
/// 以及本任务唯一的坑 —— 断行插入零宽空格后，区间必须仍能映射回显示文本。
func runClipboardSearchHighlightTests() {
    print("🧪 Testing clipboard search highlight...")
    do {
        // 单命中：区间落在词上，取出的子串就是命中词
        let single = ClipboardSearchHighlight.ranges(in: "hello world", query: "world")
        assertEqual(single.count, 1, "单命中：一段")
        assertEqual(single.first.map { String("hello world"[$0]) }, "world", "单命中：区间取出的子串正确")

        // 多命中：同一词出现两次 → 两段
        let multi = ClipboardSearchHighlight.ranges(in: "swift and swift", query: "swift")
        assertEqual(multi.count, 2, "多命中：两段")
        assertEqual(multi.map { String("swift and swift"[$0]) }, ["swift", "swift"], "多命中：两段各自正确")

        // 大小写不敏感：查询小写、正文大写
        let cased = ClipboardSearchHighlight.ranges(in: "Hello World", query: "hello")
        assertEqual(cased.count, 1, "大小写不敏感：命中一段")
        assertEqual(cased.first.map { String("Hello World"[$0]) }, "Hello", "大小写不敏感：原文大小写保留")

        // 多词 AND：两词都在才高亮，各给一段
        let andText = "git commit 与 git push"
        let and = ClipboardSearchHighlight.ranges(in: andText, query: "git push")
        assertEqual(and.count, 3, "多词 AND：git 两段 + push 一段")
        assertEqual(ClipboardSearchHighlight.ranges(in: andText, query: "git pull").isEmpty, true,
                    "多词 AND：缺一个词整条不高亮")

        // 重叠：aaa 里查 aa → 两个重叠位置合成一段
        let overlapped = ClipboardSearchHighlight.ranges(in: "aaa", query: "aa")
        assertEqual(overlapped.count, 1, "重叠：两个重叠命中合并成一段")
        assertEqual(overlapped.first.map { String("aaa"[$0]) }, "aaa", "重叠：合并后覆盖两个起点的并集")

        // 相邻：连续两词合并，不画出零宽缝隙
        let adjacent = ClipboardSearchHighlight.ranges(in: "abcdef", query: "abc cde")
        assertEqual(adjacent.count, 1, "相邻区间合并成一段")

        // 零宽空格映射：显示文本由 breakable 真实产出
        let rawURL = "https://api.example.com/v1/status"
        let displayURL = ClipboardCardTextStyle.breakable(rawURL, monospaced: true)
        assertContains(displayURL, ClipboardCardTextStyle.zeroWidthSpace, "等宽断行确实埋了零宽空格")
        let urlHits = ClipboardSearchHighlight.displayRanges(inDisplay: displayURL, query: "example")
        assertEqual(urlHits.count, 1, "零宽空格映射：跨断点词仍命中一段")
        assertEqual(urlHits.first.map { String(displayURL[$0]) }, "example",
                    "零宽空格映射：区间取出的显示子串不含零宽空格")
        // 跨断点命中：/ 后埋了零宽空格，查询串本身就跨过它
        let crossHits = ClipboardSearchHighlight.displayRanges(inDisplay: displayURL, query: "com/v1")
        assertEqual(crossHits.count, 1, "零宽空格映射：跨断点查询命中一段")
        // 跨断点的区间必然把中间的零宽空格一起覆盖：剥掉零宽空格后必须还原成原词
        let crossSlice = crossHits.first.map { String(displayURL[$0]) } ?? ""
        assertEqual(crossSlice.replacingOccurrences(of: ClipboardCardTextStyle.zeroWidthSpace, with: ""),
                    "com/v1", "零宽空格映射：跨断点区间剥掉零宽空格后等于原词")
        // 正文口径与显示口径命中数一致：说明剥零宽空格没有改变可见内容
        assertEqual(ClipboardSearchHighlight.offsetRanges(in: rawURL, query: "status").count,
                    ClipboardSearchHighlight.displayRanges(inDisplay: displayURL, query: "status").count,
                    "零宽空格映射：两种口径命中数一致")

        // 空查询 / 空白查询：不高亮
        assertEqual(ClipboardSearchHighlight.ranges(in: "anything", query: "").isEmpty, true, "空查询：不高亮")
        assertEqual(ClipboardSearchHighlight.ranges(in: "anything", query: "   ").isEmpty, true,
                    "空白查询：不高亮")

        // 查询比正文长：不高亮
        assertEqual(ClipboardSearchHighlight.ranges(in: "ab", query: "abcdef").isEmpty, true,
                    "查询比正文长：不高亮")
        assertEqual(ClipboardSearchHighlight.ranges(in: "", query: "ab").isEmpty, true, "空正文：不高亮")

        // 特殊字符：% _ \\ 按字面匹配，不当通配
        let specialText = "100% _draft_ C:\\tmp"
        assertEqual(ClipboardSearchHighlight.ranges(in: specialText, query: "100%").count, 1,
                    "特殊字符：% 按字面命中")
        assertEqual(ClipboardSearchHighlight.ranges(in: specialText, query: "_draft_").count, 1,
                    "特殊字符：_ 按字面命中")
        assertEqual(ClipboardSearchHighlight.ranges(in: specialText, query: "C:\\tmp").count, 1,
                    "特殊字符：反斜杠按字面命中")
        assertEqual(ClipboardSearchHighlight.ranges(in: specialText, query: "%").count, 1,
                    "特殊字符：单个 % 只在有 % 的地方命中")

        // 上限：单字符查询在长正文里最多 32 段
        let longText = String(repeating: "a b ", count: 40)
        let capped = ClipboardSearchHighlight.ranges(in: longText, query: "a b")
        assertEqual(capped.count, ClipboardSearchHighlight.maxRanges, "上限：段数截到 32")
        assertEqual(ClipboardSearchHighlight.maxRanges, 32, "上限常量就是 32")

        print("✅ Clipboard search highlight (ranges / AND / zero-width mapping) works")
    }
}
