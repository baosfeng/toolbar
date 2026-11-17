import Foundation

// MARK: - 剪贴板板（Pinboard）

/// 剪贴板板 — 条目分组容器，与「收藏」是两条独立语义
///
/// 归属板决定条目「永不过期 / 不参与超限清理」，`isPinned` 回归纯星标；两者叠加都豁免清理。
/// `colorIndex` 是色板下标（色值由 UI 层色板解析，Core 只存序号，换肤不动数据库）。
public struct ClipboardBoard: Equatable, Sendable, Identifiable {
    /// 色板档数：colorIndex 的有效范围是 0..<colorCount
    public static let colorCount = 8

    /// 板唯一标识
    public let id: UUID
    /// 板名（已去首尾空白，非空）
    public var name: String
    /// 色板下标
    public var colorIndex: Int
    /// 展示顺序（升序；同值按创建时间）
    public var sortOrder: Int
    /// 创建时间
    public let createdAt: Date

    public init(id: UUID = UUID(), name: String, colorIndex: Int = 0,
                sortOrder: Int = 0, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    /// 归一化板名：去首尾空白，空白输入回落到「未命名板」
    ///
    /// 板名是标签行唯一的可见文字，空名会让标签变成一颗无名色点，因此在仓储入口统一兜底。
    public static func normalizedName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名板" : trimmed
    }
}
