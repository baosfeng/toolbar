import Foundation

// MARK: - 文件条目分类聚合摘要

/// 文件条目的分类聚合摘要 — 纯函数（不依赖 AppKit / ImageIO，可直接被 TestRunner 断言）
///
/// 背景：采集侧把多文件路径按换行写进 text 列（复制回剪贴板必须还原原始路径，故 text 不动），
/// 卡片正文却只是「一串绝对路径」，用户认不出「这是什么文件」。本类型负责把它压成一句话：
/// - 单个文件 → `文档: 季度报告.pdf`
/// - 多个文件 → `文件 (2个): 文档: 季度报告.pdf; 图片 ×2: a.png、b.png`
///
/// 分族判据一律复用 `ClipboardFileClassifier`（扩展名白名单），本类型只负责族名与排版，
/// 不新增第二套分类；未知扩展名与空扩展名沿用既有 `other` 族。
public enum ClipboardFileSummary {

    /// 跨族分隔符
    public static let crossFamilySeparator = "; "

    /// 同族内文件名分隔符
    public static let intraFamilySeparator = "、"

    /// 截断省略号（超出 `ClipboardLimit.previewMaxLength` 时补在末尾）
    public static let ellipsis = "…"

    /// 多文件条目的前缀（`文件 (N个): `）
    public static func multiFilePrefix(count: Int) -> String {
        "文件 (\(count)个): "
    }

    // MARK: 族名

    /// 卡片正文用的短族名（图标与无障碍标签仍走 `ClipboardFileCategory.label` 的长名）
    ///
    /// 只做「长名 → 短名」的文案映射，分类判据仍由 `ClipboardFileClassifier` 唯一决定。
    public static func familyName(for category: ClipboardFileCategory) -> String {
        switch category {
        case .image: return "图片"
        case .video: return "视频"
        case .audio: return "音频"
        case .document: return "文档"
        case .code: return "代码"
        case .archive: return "压缩包"
        case .executable: return "可执行"
        case .other: return "文件"
        }
    }

    /// 单条路径的短族名（无法识别时落既有 `other` 族名）
    public static func familyName(forPath path: String) -> String {
        familyName(for: ClipboardFileClassifier.category(forPath: path))
    }

    /// 展示用文件名：去首尾空白后的最后一段路径；空路径返回空串
    public static func fileName(ofPath path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return (trimmed as NSString).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: 摘要

    /// 生成文件条目的摘要正文
    ///
    /// 规则：族按首次出现顺序排列（跨族顺序稳定），同族多个文件合并成一段；
    /// 尾部超长时按**条目（段）边界**截断并补省略号，宁可少显示一族，也不把文件名切成半个。
    /// - Parameters:
    ///   - paths: 原始路径列表（顺序即剪贴板中的顺序）
    ///   - maxLength: 摘要最大字符数（≤ 0 归一化为 1）
    /// - Returns: 摘要正文；空列表或全部路径都取不到文件名时返回空串
    public static func summarize(paths: [String],
                                maxLength: Int = ClipboardLimit.previewMaxLength) -> String {
        let entries = paths.compactMap { path -> Entry? in
            let name = fileName(ofPath: path)
            guard !name.isEmpty else { return nil }
            return Entry(name: name, category: ClipboardFileClassifier.category(forPath: path))
        }
        guard !entries.isEmpty else { return "" }
        let limit = max(1, maxLength)
        let items = familyItems(of: entries)
        let prefix = entries.count == 1 ? "" : multiFilePrefix(count: entries.count)
        return assemble(prefix: prefix, items: items, limit: limit)
    }

    /// 生成文件条目的摘要正文；取不到任何文件名时回落到调用方给的原始文本
    ///
    /// 采集侧只调这一个入口：路径异常（全为空串等）时卡片仍显示旧口径，
    /// 不会因为摘要生成不出而变成空卡片。
    /// - Parameters:
    ///   - paths: 原始路径列表
    ///   - fallbackText: 摘要为空时的回落文本（通常是文件的 text 列）
    ///   - maxLength: 摘要最大字符数（≤ 0 归一化为 1）
    public static func summarize(paths: [String],
                                fallbackText: String,
                                maxLength: Int = ClipboardLimit.previewMaxLength) -> String {
        let summary = summarize(paths: paths, maxLength: maxLength)
        return summary.isEmpty ? ClipboardPreview.make(from: fallbackText, maxLength: maxLength) : summary
    }

    // MARK: 内部实现

    /// 一条待展示的文件（分类 + 文件名）
    private struct Entry {
        let name: String
        let category: ClipboardFileCategory
    }

    /// 一个可拼接单元：族头（`文档 ×2: `）或一个文件名（含它的分隔符）
    ///
    /// 拆到文件名粒度是为了让截断能落在「完整文件名」边界，
    /// 同族合并段（`文档 ×2: a、b`）里也不会把第二个名字切成半个。
    private struct Item {
        /// 该单元自带的文本（含它前面的跨族分隔符 / 族内顿号）
        let text: String
        /// 是否为族头（族头后面必须跟至少一个文件名才算完整）
        let isFamilyHead: Bool
    }

    /// 按首次出现顺序把条目切成单元序列：族头 + 族内逐个文件名
    private static func familyItems(of entries: [Entry]) -> [Item] {
        var order: [ClipboardFileCategory] = []
        var grouped: [ClipboardFileCategory: [String]] = [:]
        for entry in entries {
            if grouped[entry.category] == nil { order.append(entry.category) }
            grouped[entry.category, default: []].append(entry.name)
        }
        var items: [Item] = []
        for (familyIndex, category) in order.enumerated() {
            let names = grouped[category] ?? []
            let family = familyName(for: category)
            let separator = familyIndex == 0 ? "" : crossFamilySeparator
            let head = names.count > 1
                ? "\(separator)\(family) ×\(names.count): "
                : "\(separator)\(family): "
            items.append(Item(text: head, isFamilyHead: true))
            for (index, name) in names.enumerated() {
                let glue = index == 0 ? "" : intraFamilySeparator
                items.append(Item(text: glue + name, isFamilyHead: false))
            }
        }
        return items
    }

    /// 逐单元拼接：整体放得下就原样返回；放不下则回退到最后一个「完整文件名」边界并补省略号
    ///
    /// 边界口径：族头后面没有文件名时不算完整，回退时把族头一起去掉，
    /// 因此截断结果不会以 `; `、`、` 或 `文档: ` 这类半截前缀收尾。
    private static func assemble(prefix: String, items: [Item], limit: Int) -> String {
        let full = prefix + items.map(\.text).joined()
        guard full.count > limit else { return full }
        var snapshot = prefix
        var lastBoundary: String?
        for item in items {
            let candidate = snapshot + item.text
            // 顺序拼接：第一个放不下的条目之后的都丢掉，避免跳条目造成语义错位
            guard candidate.count <= limit else { break }
            snapshot = candidate
            // 边界必须给省略号留位置，否则末尾补不上省略号、只剩硬截断
            if !item.isFamilyHead, candidate.count + ellipsis.count <= limit {
                lastBoundary = candidate
            }
        }
        if let lastBoundary {
            return lastBoundary + ellipsis
        }
        // 连一个完整文件名都放不下（单个超长文件名，或上限被压到很小）：
        // 只保留「文件 (N个): 」与首个族头再收尾，绝不把某个文件名切成半个
        let head = prefix + (items.first(where: { $0.isFamilyHead })?.text ?? "")
        let trimmed = clipped(head, limit: limit)
        guard !trimmed.hasSuffix(ellipsis), trimmed.count + ellipsis.count <= limit else { return trimmed }
        return trimmed + ellipsis
    }

    /// 按字符硬截断并补省略号（仅在连一个完整文件名都放不下时使用）
    private static func clipped(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        guard limit > ellipsis.count else { return String(text.prefix(limit)) }
        return String(text.prefix(limit - ellipsis.count)) + ellipsis
    }
}
