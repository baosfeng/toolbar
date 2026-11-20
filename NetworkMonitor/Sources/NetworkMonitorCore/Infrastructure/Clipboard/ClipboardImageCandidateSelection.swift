import Foundation

// MARK: - 剪贴板图片候选选择（字节上限语义）

/// 一次剪贴板图片的选择结果
///
/// `isOversized` 为 true 时表示：唯一可读的表示已经超过单图字节上限，
/// 调用方**不得落盘**，只能按头部尺寸产出「原图过大未保存」的占位记录。
public struct ClipboardImageSelection: Equatable, Sendable {
    /// 命中的类型名（白名单命中时是规范名，如 `public.png`）
    public let typeName: String
    /// 该类型的原始字节
    public let data: Data
    /// 原始字节是否已超单图上限
    public let isOversized: Bool

    public init(typeName: String, data: Data, isOversized: Bool) {
        self.typeName = typeName
        self.data = data
        self.isOversized = isOversized
    }
}

/// 从候选表示里选一个（纯函数，测试可直接断言取舍）
///
/// 取舍口径：
/// 1. 优先「不超过上限」的第一个候选（顺序由 `ClipboardImageFormat.orderedCandidates` 给出，PNG 在 TIFF 前）；
/// 2. 全部超限时取第一个超限候选并标 `isOversized`——**不再静默丢弃**。
///    旧实现直接 `continue`，只提供未压缩 TIFF 的全屏截图（22MB）在历史里整条消失，
///    用户只能看到「复制了但没有」，而原因是 debug 级日志、默认不落盘。
public enum ClipboardImageCandidateSelection {

    /// 选一个表示
    /// - Parameters:
    ///   - candidates: 按优先级排好的候选（同一次复制只取一个）
    ///   - maxBytes: 单图字节上限（≤ 0 时取 `ClipboardLimit.maxImageBytes`）
    /// - Returns: 选择结果；无候选或全部为空字节时返回 nil
    public static func select(candidates: [ClipboardImageFormat.Selection],
                              maxBytes: Int) -> ClipboardImageSelection? {
        let limit = maxBytes > 0 ? maxBytes : ClipboardLimit.maxImageBytes
        var oversized: ClipboardImageFormat.Selection?
        for candidate in candidates {
            guard !candidate.data.isEmpty else { continue }
            if candidate.data.count <= limit {
                return ClipboardImageSelection(typeName: candidate.typeName,
                                               data: candidate.data,
                                               isOversized: false)
            }
            if oversized == nil { oversized = candidate }
        }
        guard let oversized else { return nil }
        return ClipboardImageSelection(typeName: oversized.typeName,
                                       data: oversized.data,
                                       isOversized: true)
    }
}
