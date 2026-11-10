import Foundation

// MARK: - 贴图内容源（图片文件）

/// 图片文件贴图结果
public enum SnipImageFilePinOutcome: Equatable, Sendable {
    /// 贴图像（路径供日志与取图）
    case image(path: String)
    /// 把文件路径当文本贴出
    case pathText
}

/// 「本次会话内已贴为图像」的文件记录（路径 + 内容哈希）
///
/// 对齐 Snipaste 内容源口径：「图像贴出后再贴，会把文件路径当做文本贴出」。
/// 内容哈希取不到时用空值占位，此时只按路径判重（宁多降级一次，不重复贴大图）。
public enum SnipImageFilePinTracker {

    /// 判重签名 = 文件路径 + 内容哈希
    public static func signature(path: String, contentHash: String?) -> String {
        "\(path)#\(contentHash ?? "")"
    }

    /// 该文件是否已在本次会话里贴过图像
    public static func isPinned(_ signatures: Set<String>, path: String, contentHash: String?) -> Bool {
        signatures.contains(signature(path: path, contentHash: contentHash))
    }

    /// 记录「本次会话已贴为图像」（返回新集合，便于测试与无状态调用方）
    public static func recording(_ signatures: Set<String>, path: String, contentHash: String?) -> Set<String> {
        var next = signatures
        next.insert(signature(path: path, contentHash: contentHash))
        return next
    }
}

/// 图片文件贴图策略（纯函数）
///
/// 判定顺序：偏好关掉「优先显示图像」→ 一律路径文本；已贴过 → 路径文本；否则贴图像。
public enum SnipImageFilePinPolicy {

    /// - Parameters:
    ///   - path: 图片文件路径
    ///   - contentHash: 文件内容哈希（nil 表示取不到）
    ///   - displayImageFiles: 偏好「图片文件贴图时优先显示图像」（默认开）
    ///   - pinnedSignatures: 本次会话内已贴为图像的文件签名
    public static func outcome(path: String,
                               contentHash: String?,
                               displayImageFiles: Bool,
                               pinnedSignatures: Set<String>) -> SnipImageFilePinOutcome {
        guard displayImageFiles else { return .pathText }
        guard !SnipImageFilePinTracker.isPinned(pinnedSignatures, path: path, contentHash: contentHash) else {
            return .pathText
        }
        return .image(path: path)
    }
}

/// 文件路径转贴图文本
public enum SnipFilePathText {

    /// 把文件路径拼成贴图正文：每行一条，去首尾空白与重复项；没有有效路径返回 nil
    public static func joined(_ paths: [String]) -> String? {
        var seen = Set<String>()
        let lines = paths.compactMap { raw -> String? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

// MARK: - 内容指纹

/// 图片文件内容指纹 — 读字节算 SHA256，超过字节上限返回 nil（退化为仅按路径判重）
public enum SnipImageFileFingerprint {

    /// - Parameters:
    ///   - path: 文件路径
    ///   - maxBytes: 参与哈希的字节上限（≤ 0 时取 ClipboardLimit.maxImageBytes）
    public static func contentHash(ofFileAt path: String, maxBytes: Int = ClipboardLimit.maxImageBytes) -> String? {
        guard !path.isEmpty,
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attributes[.size] as? NSNumber)?.intValue,
              size > 0 else { return nil }
        let limit = maxBytes > 0 ? maxBytes : ClipboardLimit.maxImageBytes
        guard size <= limit,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
              !data.isEmpty else { return nil }
        return ClipboardContentHasher.sha256Hex(data)
    }
}

// MARK: - 已关闭贴图恢复队列

/// 可被恢复的已关闭贴图数 — 官方默认 1，可在选项里调整
public enum SnipClosedPinLimit {

    /// 默认张数（官方「默认建议 1」）
    public static let defaultValue = 1
    /// 允许的取值范围
    public static let range = 1...10

    /// 把偏好值夹到合法范围：未设置读到 0 时回落到默认值
    public static func normalized(_ raw: Int) -> Int {
        min(max(raw, range.lowerBound), range.upperBound)
    }
}

/// 已关闭贴图恢复队列（纯逻辑：入队在最前，按上限裁剪）
public enum SnipClosedPinRecoveryQueue {

    /// 按上限裁剪：保留最前面的条目（最近关闭的优先恢复）
    public static func trimmed<T>(_ items: [T], limit: Int) -> [T] {
        let capped = SnipClosedPinLimit.normalized(limit)
        return items.count > capped ? Array(items.prefix(capped)) : items
    }

    /// 入队（最新在最前）后按上限裁剪
    public static func enqueue<T>(_ item: T, into queue: [T], limit: Int) -> [T] {
        trimmed([item] + queue, limit: limit)
    }
}
