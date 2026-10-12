import Foundation

// MARK: - 条目类型

/// 剪贴板条目类型（raw value 直接对应数据库 kind 列）
public enum ClipboardItemKind: String, Sendable, CaseIterable {
    /// 纯文本
    case text
    /// 图片（原图落盘为 PNG，DB 只存路径与尺寸）
    case image
    /// 文件 URL（text 字段存 URL 摘要文本）
    case file
    /// 富文本 RTF
    case rtf
}

// MARK: - 历史条目

/// 剪贴板历史条目 — 值类型，跨线程传递安全
///
/// 字段与 `clipboard_items` 表一一对应；`isPinned` 同时承担「收藏」（卡片星标）语义，
/// 收藏项豁免清空与超限清理。
public struct ClipboardItem: Equatable, Sendable, Identifiable {
    /// 条目唯一标识（命中内容去重时保留库中原 id）
    public let id: UUID
    /// 内容类型
    public var kind: ClipboardItemKind
    /// 正文（图片条目为 nil；超长文本已在采集侧按上限截断）
    public var text: String?
    /// 摘要（折叠换行 + 尾部截断，卡片视图与搜索使用）
    public var preview: String
    /// 图片原图路径（仅 image 条目）
    public var imagePath: String?
    /// 图片像素宽
    public var imageWidth: Int?
    /// 图片像素高
    public var imageHeight: Int?
    /// 内容哈希（去重口径，库中唯一）
    public var contentHash: String
    /// 来源 App bundleID
    public var sourceBundleID: String?
    /// 来源 App 名称
    public var sourceAppName: String?
    /// 复制次数（同一内容再次复制时自增）
    public var copyCount: Int
    /// 是否收藏（收藏项豁免清空与超限清理）
    public var isPinned: Bool
    /// 创建时间（复制时间，重复复制会刷新以置顶）
    public var createdAt: Date
    /// 收藏时间
    public var pinnedAt: Date?
    /// Paste Stack 顺序（nil = 不在栈内，从 1 开始编号）
    public var stackPosition: Int?

    public init(
        id: UUID = UUID(),
        kind: ClipboardItemKind,
        text: String? = nil,
        preview: String = "",
        imagePath: String? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        contentHash: String,
        sourceBundleID: String? = nil,
        sourceAppName: String? = nil,
        copyCount: Int = 1,
        isPinned: Bool = false,
        createdAt: Date = Date(),
        pinnedAt: Date? = nil,
        stackPosition: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.preview = preview
        self.imagePath = imagePath
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.contentHash = contentHash
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.copyCount = copyCount
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.pinnedAt = pinnedAt
        self.stackPosition = stackPosition
    }

    /// 是否为图片条目（卡片视图按类型分支绘制）
    public var isImage: Bool { kind == .image }

    /// 是否已入 Paste Stack
    public var isInStack: Bool { stackPosition != nil }
}

// MARK: - 采集草稿

/// 采集结果草稿 — 采集服务产出、仓储落库的入参
///
/// 不含 id：新行由仓储生成 UUID；命中 content_hash 冲突时保留库中原 id 并自增 copy_count。
public struct ClipboardDraft: Equatable, Sendable {
    /// 内容类型
    public var kind: ClipboardItemKind
    /// 正文（图片条目为 nil）
    public var text: String?
    /// 摘要；nil 时由仓储按 text 自动生成
    public var preview: String?
    /// 图片原图路径
    public var imagePath: String?
    /// 图片像素宽
    public var imageWidth: Int?
    /// 图片像素高
    public var imageHeight: Int?
    /// 内容哈希（由 ClipboardContentHasher 产出，空串一律不落库）
    public var contentHash: String
    /// 来源 App bundleID
    public var sourceBundleID: String?
    /// 来源 App 名称
    public var sourceAppName: String?
    /// 复制时间
    public var createdAt: Date

    public init(
        kind: ClipboardItemKind,
        contentHash: String,
        text: String? = nil,
        preview: String? = nil,
        imagePath: String? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        sourceBundleID: String? = nil,
        sourceAppName: String? = nil,
        createdAt: Date = Date()
    ) {
        self.kind = kind
        self.contentHash = contentHash
        self.text = text
        self.preview = preview
        self.imagePath = imagePath
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.createdAt = createdAt
    }
}

// MARK: - 摘要生成

/// 条目摘要生成 — 折叠换行 + 尾部截断（卡片视图、数据库 preview 列共用同一口径）
public enum ClipboardPreview {
    /// 生成摘要
    ///
    /// 规则：换行/制表符/连续空白折叠为单个空格并去首尾空白；超长时按字符尾部截断，
    /// 末位替换为省略号，保证结果长度不超过 maxLength。空白输入返回空串。
    /// - Parameters:
    ///   - text: 原始文本
    ///   - maxLength: 摘要最大字符数（≤ 0 归一化为 1）
    public static func make(from text: String, maxLength: Int = ClipboardLimit.previewMaxLength) -> String {
        let limit = max(1, maxLength)
        let folded = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard folded.count > limit else { return folded }
        return String(folded.prefix(limit - 1)) + "…"
    }
}
