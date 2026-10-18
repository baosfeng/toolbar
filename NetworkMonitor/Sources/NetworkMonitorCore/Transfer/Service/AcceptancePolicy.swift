import Foundation

// MARK: - 接收放行策略

/// 接收端放行策略 — 决定一次 `offer` 是否需要 PIN 确认（设计文档 §3.6）
///
/// 三条放行规则 **OR** 关系：已配对 / 免配对窗口生效 / 文件总大小落在阈值内；
/// 都不满足才返回 `pending` 并生成 PIN。放行不等于建立长期配对（不签发 `pairingKey`）。
public enum AcceptancePolicy {

    /// 放行原因（日志与 UI 提示用）
    public enum Reason: String, Sendable, Equatable {
        /// 已配对（`X-Pair-Key` 校验通过）
        case paired
        /// 免配对窗口生效
        case autoAcceptWindow
        /// 体积阈值命中
        case sizeThreshold
        /// 都不满足，需要 PIN
        case requiresPIN
    }

    /// 决策结果
    public struct Decision: Equatable, Sendable {
        /// 是否免确认
        public let accepted: Bool
        /// 命中原因
        public let reason: Reason

        public init(accepted: Bool, reason: Reason) {
            self.accepted = accepted
            self.reason = reason
        }
    }

    /// 计算本次 offer 的放行决策
    ///
    /// - Parameters:
    ///   - paired: `X-Pair-Key` 是否与本地配对记录一致
    ///   - windowActive: 免配对窗口当前是否生效
    ///   - sizeThresholdMB: 体积阈值（MB），0 表示关闭
    ///   - totalBytes: 本次 offer 的文件总大小
    public static func decide(paired: Bool, windowActive: Bool,
                              sizeThresholdMB: Int, totalBytes: Int64) -> Decision {
        if paired {
            return Decision(accepted: true, reason: .paired)
        }
        if windowActive {
            return Decision(accepted: true, reason: .autoAcceptWindow)
        }
        if sizeThresholdMB > 0, totalBytes >= 0,
           totalBytes <= Int64(sizeThresholdMB) * 1024 * 1024 {
            return Decision(accepted: true, reason: .sizeThreshold)
        }
        return Decision(accepted: false, reason: .requiresPIN)
    }
}

// MARK: - 接收目录统计

/// 接收目录统计 — 文件数与总字节，供设置窗展示与清理
public enum ReceiveDirectoryStats {

    /// 统计结果
    public struct Summary: Equatable, Sendable {
        /// 文件个数
        public var fileCount: Int
        /// 总字节
        public var totalBytes: Int64

        public init(fileCount: Int = 0, totalBytes: Int64 = 0) {
            self.fileCount = fileCount
            self.totalBytes = totalBytes
        }

        /// 空目录
        public static let empty = Summary()
    }

    /// 纯函数：按文件大小汇总（负值按 0 计）
    public static func summarize(sizes: [Int64]) -> Summary {
        Summary(fileCount: sizes.count, totalBytes: sizes.reduce(0) { $0 + max(0, $1) })
    }

    /// 列出目录中的普通文件（不递归、不跟随子目录）
    public static func files(in directory: URL, fileManager: FileManager = .default) -> [URL] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]) else {
            return []
        }
        return entries.filter { url in
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true
        }
    }

    /// 扫描目录并汇总（跳过子目录）
    public static func scan(directory: URL, fileManager: FileManager = .default) -> Summary {
        let urls = files(in: directory, fileManager: fileManager)
        let sizes = urls.map { url -> Int64 in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            return Int64(values?.fileSize ?? 0)
        }
        return summarize(sizes: sizes)
    }
}
