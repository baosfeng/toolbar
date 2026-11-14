import Foundation

// MARK: - 缩略图加载闸门

/// 缩略图后台解码闸门（纯状态机：无 Dispatch / 无 AppKit 依赖，可直接被 TestRunner 断言）
///
/// 两条判定，全部收在这一处，调用方与测试共用同一口径：
/// 1. 并发上限：在途解码数不得超过 `maxConcurrent`（默认 3，对标 OneClip 的 Semaphore(3)）；
/// 2. 在途去重：同一 contentHash 正在解码时再次 beginLoad 一律拒绝，避免同一张图重复解码。
///
/// 失败是否可重试**不在这里判定**：冷却与次数上限由 `ClipboardThumbnailRetryPolicy` 唯一决定，
/// 闸门只管「同时解几张、同一张不重复解」，避免两处各存一套失败记忆。
/// 额度归还在解码结束时由调用方显式 `finishLoad`：成功与失败都必须归还，
/// 否则闸门会被一次失败永久卡死。
public struct ClipboardThumbnailLoadGate: Sendable {

    /// 默认并发上限
    public static let defaultMaxConcurrent = 3

    /// 并发上限（构造入参 ≤ 0 时归一化为默认值，避免「上限 0 等于永久阻塞」）
    public let maxConcurrent: Int

    /// 在途 hash
    private var inFlightHashes: Set<String> = []

    public init(maxConcurrent: Int = defaultMaxConcurrent) {
        self.maxConcurrent = maxConcurrent > 0 ? maxConcurrent : Self.defaultMaxConcurrent
    }

    /// 已占用的并发额度（一个 hash 恰好占一个额度，故与在途数恒等）
    public var activeCount: Int { inFlightHashes.count }

    /// 在途 hash 数（诊断口径，与 activeCount 恒等）
    public var inFlightCount: Int { inFlightHashes.count }

    /// 剩余可用额度
    public var availableSlots: Int { max(0, maxConcurrent - inFlightHashes.count) }

    /// 该 hash 是否正在解码
    public func isInFlight(hash: String) -> Bool { inFlightHashes.contains(normalized(hash)) }

    /// 登记一次加载：未在途且并发未满才返回 true（其余情况调用方不入队、不回调）
    public mutating func beginLoad(hash: String) -> Bool {
        let key = normalized(hash)
        guard !key.isEmpty,
              !inFlightHashes.contains(key),
              inFlightHashes.count < maxConcurrent else { return false }
        inFlightHashes.insert(key)
        return true
    }

    /// 归还额度并清理在途登记；不在途时无操作（重复调用幂等）
    public mutating func finishLoad(hash: String) {
        inFlightHashes.remove(normalized(hash))
    }

    /// 清空在途登记（面板收起 / 重新打开时调用；失败记忆不在这里，见 `ClipboardThumbnailRetryPolicy`）
    public mutating func reset() {
        inFlightHashes.removeAll()
    }

    /// hash 归一化：去首尾空白（空白 hash 视为非法入参，一律拒绝）
    private func normalized(_ hash: String) -> String {
        hash.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
