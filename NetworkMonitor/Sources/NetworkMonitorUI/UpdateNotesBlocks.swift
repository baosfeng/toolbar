import Foundation

// MARK: - 发布说明分块

/// 发布说明块 — 只识别「够读」的最小子集：标题 / 条目 / 段落
///
/// 为什么不引 markdown 库：关于页只需要三档块（小标题、项目符号条目、正文段），
/// 完整渲染器的表格 / 代码块 / 嵌套列表在本仓 release notes 里从不出现，
/// 引进来只是多一个依赖与一整套解析面。
///
/// 识别口径（与 `UpdateNotes.blocks` 一致）：
/// - `## 标题`（1–6 个 `#`）→ heading；
/// - `- 条目` / `* 条目` / `+ 条目` / `• 条目` / `1. 条目` → bullet；
/// - `**粗体**` 不是条目（符号后面必须跟空白才算），其余连续行合成段落；
/// - 空行与整行 HTML 注释是段落边界，本身不产出块。
public enum ReleaseNoteBlock: Equatable, Sendable {
    /// 小标题（层级已剥掉，界面统一按同一档渲染）
    case heading(String)
    /// 条目
    case bullet(String)
    /// 正文段（块内多行已用空格拼成一段）
    case paragraph(String)

    /// 块的原始文本（仍带行内标记，供渲染层决定强调）
    public var rawText: String {
        switch self {
        case .heading(let text), .bullet(let text), .paragraph(let text):
            return text
        }
    }

    /// 纯文本（剥掉行内标记；读屏 / tooltip / 取证共用这一份）
    public var plainText: String { ReleaseNoteInline.plain(rawText) }
}

// MARK: - 行内标记

/// 行内标记清洗 —— 界面要的是「读得懂的字」，不是 markdown 原文
public enum ReleaseNoteInline {

    /// 去掉粗体星号、行内代码反引号、链接目标的括号部分，只留文字
    public static func plain(_ text: String) -> String {
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            // 粗体 / 斜体标记：成对星号只吃标记、留字
            if character == "*" {
                index = text.index(after: index)
                continue
            }
            // 行内代码标记
            if character == "\u{60}" {
                index = text.index(after: index)
                continue
            }
            // 链接文字的开括号：丢弃
            if character == "[" {
                index = text.index(after: index)
                continue
            }
            // 链接目标：`](http://...)` 整段吃掉
            if character == "]",
               let parenStart = text.index(index, offsetBy: 1, limitedBy: text.endIndex),
               parenStart < text.endIndex, text[parenStart] == "(",
               let close = text[parenStart...].firstIndex(of: ")") {
                index = text.index(after: close)
                continue
            }
            result.append(character)
            index = text.index(after: index)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// 行内链接目标（`[文字](url)` → url；没有链接为 nil）
    ///
    /// 说明区要把提交短哈希旁的真实地址留成可复制 / 可点开的一行，
    /// 所以地址必须单独取出来——它不会出现在纯文本里。
    public static func firstLink(_ text: String) -> String? {
        guard let open = text.firstIndex(of: "]"),
              let parenStart = text.index(open, offsetBy: 1, limitedBy: text.endIndex),
              parenStart < text.endIndex, text[parenStart] == "(",
              let close = text[parenStart...].firstIndex(of: ")") else { return nil }
        let url = text[text.index(after: parenStart)..<close].trimmingCharacters(in: .whitespaces)
        return url.isEmpty ? nil : url
    }
}

// MARK: - 说明区行模型

/// 一行说明的渲染档
public enum ReleaseNoteLineStyle: Equatable, Sendable {
    /// 小标题（加粗、上方留空）
    case heading
    /// 项目符号条目
    case bullet
    /// 正文段
    case paragraph
    /// 截断提示（不再是原说明内容）
    case truncationNotice
}

/// 说明区的一行 —— 视图只认这个模型，不再自己判断谁是标题谁是条目
public struct ReleaseNoteLine: Equatable, Sendable {
    /// 展示文本（已剥行内标记）
    public let text: String
    /// 渲染档
    public let style: ReleaseNoteLineStyle

    public init(text: String, style: ReleaseNoteLineStyle) {
        self.text = text
        self.style = style
    }
}

// MARK: - UpdateNotes 的分块能力

extension UpdateNotes {

    /// 说明区最多展示的行数 —— 超出不再堆内容，尾部补一行截断提示
    ///
    /// 为什么要有上限：说明区是固定高度的内部滚动区，无限长会变成「滚很久才到底」；
    /// 超长 body（本仓当前版本 40+ 条）全渲染进 attributed string 也没人读完。
    public static let blockLineLimit = 200

    /// 截断提示文案（同时也是「完整内容在发布页」的出口）
    public static let truncationNotice = "…（还有更多条目，完整说明见发布页）"

    /// 发布说明正文 → 分块
    public static func blocks(_ raw: String) -> [ReleaseNoteBlock] {
        var result: [ReleaseNoteBlock] = []
        var paragraph: [String] = []

        func flushParagraph() {
            let text = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            paragraph.removeAll()
            guard !text.isEmpty else { return }
            result.append(.paragraph(text))
        }

        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // 空行与整行 HTML 注释都是段落边界（生成的 release notes 里注释是单行）
            guard !line.isEmpty, !line.hasPrefix("<!--") else {
                flushParagraph()
                continue
            }
            if let title = headingText(line) {
                flushParagraph()
                result.append(.heading(title))
                continue
            }
            if let item = bulletText(line) {
                flushParagraph()
                result.append(.bullet(item))
                continue
            }
            paragraph.append(strippingQuote(line))
        }
        flushParagraph()
        return result
    }

    /// 分块 → 说明区行（带渲染档与行数上限）
    public static func lines(_ raw: String, limit: Int = blockLineLimit) -> [ReleaseNoteLine] {
        makeLines(blocks(raw), limit: limit)
    }

    /// 分块（已有）→ 说明区行
    public static func lines(from blocks: [ReleaseNoteBlock], limit: Int = blockLineLimit) -> [ReleaseNoteLine] {
        makeLines(blocks, limit: limit)
    }

    // MARK: 私有

    private static func makeLines(_ blocks: [ReleaseNoteBlock], limit: Int) -> [ReleaseNoteLine] {
        var lines: [ReleaseNoteLine] = []
        for block in blocks {
            let text = block.plainText
            guard !text.isEmpty else { continue }
            switch block {
            case .heading:
                lines.append(ReleaseNoteLine(text: text, style: .heading))
            case .bullet:
                lines.append(ReleaseNoteLine(text: text, style: .bullet))
            case .paragraph:
                lines.append(ReleaseNoteLine(text: text, style: .paragraph))
            }
        }
        guard limit > 0, lines.count > limit else { return lines }
        // 留一行位置给截断提示：展示行数永远不超过上限
        let kept = limit > 1 ? Array(lines.prefix(limit - 1)) : []
        return kept + [ReleaseNoteLine(text: truncationNotice, style: .truncationNotice)]
    }

    /// `## 标题` → 标题文本（1–6 个井号且后面必须是行尾或空白）
    private static func headingText(_ line: String) -> String? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return nil }
        let rest = line.dropFirst(hashes.count)
        guard rest.isEmpty || rest.first?.isWhitespace == true else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : ReleaseNoteInline.plain(text)
    }

    /// 条目行 → 文本（保序：无序符号归一成 `- `，有序列表保留数字）
    ///
    /// 为什么保留标记：界面渲染时「•」由视图自己加，而有序列表的 `1. ` 是内容的一部分，
    /// 剥掉会让「第一步 / 第二步」变成两条看不出顺序的平铺条目。
    private static func bulletText(_ line: String) -> String? {
        for marker in ["-", "*", "+", "•"]
        where line.hasPrefix(marker + " ") || line.hasPrefix(marker + "\t") {
            let text = line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
            // 无序符号统一成 `-`：三种符号在 GitHub 上是同一种列表，界面不必区分
            if !text.isEmpty { return "- " + text }
        }
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        let text = rest.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : digits + ". " + text
    }

    /// 去掉引用行的 `>` 前缀（GitHub notes 里 `> 注意` 当段落读）
    private static func strippingQuote(_ line: String) -> String {
        var text = line
        while let first = text.first, first == ">" {
            text.removeFirst()
            text = text.trimmingCharacters(in: .whitespaces)
        }
        return text
    }
}