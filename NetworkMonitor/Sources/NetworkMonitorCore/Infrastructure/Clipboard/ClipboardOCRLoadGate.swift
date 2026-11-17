import Foundation

// MARK: - 识别闸门

/// 图片文字识别的后台闸门（纯状态机：无 Dispatch / 无 AppKit 依赖，可直接被 TestRunner 断言）
///
/// 与缩略图闸门（`ClipboardThumbnailLoadGate`）同构但独立：键是条目 id 而不是内容哈希，
/// 并发上限也低一档（识别比降采样贵一个量级）。两条判定全部收在这一处：
/// 1. 并发上限：在途识别数不得超过 `maxConcurrent`；
/// 2. 在途去重：同一条目正在识别时再次 beginLoad 一律拒绝。
///
/// 失败能否重试**不在这里判定**：冷却与次数上限由 `ClipboardOCRRetryPolicy` 唯一决定。
/// 额度归还在识别结束时由调用方显式 `finishLoad`：成功与失败都必须归还。
public struct ClipboardOCRLoadGate: Sendable {

    /// 默认并发上限（Vision accurate 档单张约 100–300ms，2 路足够让采集后的一批图排完队）
    public static let defaultMaxConcurrent = 2

    /// 并发上限（构造入参 ≤ 0 时归一化为默认值，避免「上限 0 等于永久阻塞」）
    public let maxConcurrent: Int

    /// 在途 key（条目 id）
    private var inFlightKeys: Set<String> = []

    public init(maxConcurrent: Int = defaultMaxConcurrent) {
        self.maxConcurrent = maxConcurrent > 0 ? maxConcurrent : Self.defaultMaxConcurrent
    }

    /// 已占用的并发额度
    public var activeCount: Int { inFlightKeys.count }

    /// 剩余可用额度
    public var availableSlots: Int { max(0, maxConcurrent - inFlightKeys.count) }

    /// 该条目是否正在识别
    public func isInFlight(key: String) -> Bool { inFlightKeys.contains(normalized(key)) }

    /// 登记一次识别：未在途且并发未满才返回 true（其余情况调用方不入队、不回调）
    public mutating func beginLoad(key: String) -> Bool {
        let key = normalized(key)
        guard !key.isEmpty,
              !inFlightKeys.contains(key),
              inFlightKeys.count < maxConcurrent else { return false }
        inFlightKeys.insert(key)
        return true
    }

    /// 归还额度并清理在途登记；不在途时无操作（重复调用幂等）
    public mutating func finishLoad(key: String) {
        inFlightKeys.remove(normalized(key))
    }

    /// 清空在途登记（退出 / 会话重置时调用；失败记忆不在这里）
    public mutating func reset() {
        inFlightKeys.removeAll()
    }

    /// key 归一化：去首尾空白（空白 key 视为非法入参，一律拒绝）
    private func normalized(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
