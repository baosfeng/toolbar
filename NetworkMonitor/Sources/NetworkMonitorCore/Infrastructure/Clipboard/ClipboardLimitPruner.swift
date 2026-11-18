import Foundation

// MARK: - 剪贴板超限清理编排（纯编排，可单测）

/// 一轮「超限清理」的编排 —— 放在 Core 而不是 App 层，是因为**顺序本身是行为**：
/// 先按条数还是先按容量、两轮结果怎么合并，都要能被 TestRunner 直接断言，
/// 而不是散在只跑得起来的 App 目标里、只能靠人工点界面确认。
///
/// 顺序：**先按条数（含保留天数），再按容量**。
/// 理由：条数清理是既有的、语义最直接的一步，先把「条数已经超了」的条目删掉；
/// 随后容量清理只需在剩下的条目上从最旧往新删，不会出现两轮各自删一批、
/// 各自回收一次文件的重复 IO，也不会出现「按容量删到一半、按条数再判一次」的反复。
///
/// 两条路径都走仓储的删除接口（`pruneClipboardItems` / `pruneClipboardItemsOverCapacity`），
/// 二者内部都复用 `clipDeleteBatch`（先取被删行、再删行、单事务），
/// 因此上层回收落盘图片对两条路径是同一份代码。
public enum ClipboardLimitPruner {

    /// 一轮清理的结果（按两条规则分列，便于调用方分别记日志与断言）
    public struct Outcome: Equatable, Sendable {
        /// 按条数 / 保留天数被删的条目
        public let byCount: [ClipboardItem]
        /// 按容量上限被删的条目
        public let byCapacity: [ClipboardItem]

        public init(byCount: [ClipboardItem], byCapacity: [ClipboardItem]) {
            self.byCount = byCount
            self.byCapacity = byCapacity
        }

        /// 本轮被删的全部条目（图片回收按它一次性处理）
        public var removed: [ClipboardItem] { byCount + byCapacity }
        /// 本轮删除条数
        public var removedCount: Int { byCount.count + byCapacity.count }
        /// 是否什么都没删（调用方可据此跳过事件广播 / 文件系统操作）
        public var isEmpty: Bool { byCount.isEmpty && byCapacity.isEmpty }
    }

    /// 执行一轮超限清理
    /// - Parameters:
    ///   - repository: 剪贴板仓储（按容量那半按能力探测，缺能力时静默跳过）
    ///   - maxItems: 最大条数（≤ 0 由仓储归一化为默认值）
    ///   - retentionDays: 保留天数（≤ 0 由仓储归一化为默认值）
    ///   - maxBytes: 最大容量字节（0 = 不限，跳过容量清理）
    ///   - imageByteCount: 图片原图路径 → 文件字节（容量口径见 `ClipboardCapacityUsage`）
    public static func prune(repository: any ClipboardRepository,
                             maxItems: Int, retentionDays: Int, maxBytes: UInt64,
                             imageByteCount: (String) -> UInt64) -> Outcome {
        let byCount = repository.pruneClipboardItems(maxItems: maxItems, retentionDays: retentionDays)
        let byCapacity = pruneOverCapacity(repository: repository, maxBytes: maxBytes,
                                          imageByteCount: imageByteCount)
        return Outcome(byCount: byCount, byCapacity: byCapacity)
    }

    /// 只做容量清理（启动清理入口用它：按条数在每次写入后已持续兜住，冷启动不必重跑）
    public static func pruneOverCapacity(repository: any ClipboardRepository, maxBytes: UInt64,
                                         imageByteCount: (String) -> UInt64) -> [ClipboardItem] {
        guard maxBytes != ClipboardCapacityUsage.unlimited,
              // 仓储缺这条能力（旧 mock / 测试替身）时静默跳过，按条数清理照常生效
              let capacity = repository as? any ClipboardCapacityPruneRepository else { return [] }
        return capacity.pruneClipboardItemsOverCapacity(maxBytes: maxBytes, imageByteCount: imageByteCount)
    }
}
