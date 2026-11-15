import Foundation

#if DEBUG
// MARK: - 快照证据行写入（仅 DEBUG）

/// 设置页「控件状态 / 偏好真值」证据行的落盘辅助
///
/// 为什么需要去重：同一 tag 的证据行原先一律追加，而快照流程里同一页可能被装配两次
/// （首屏 + 滚动到底取证），于是同一个 `[snapshot]` 行会写两三遍，导致同一份代码
/// 连跑两次产出的 txt 内容不同（行数 1 / 2 随机）—— txt 也就失去了逐字对账的意义。
///
/// 口径：**同一 tag 只保留一行**，后写的覆盖先写的。不同 tag（如 `[scrolled]`）各自保留。
enum SnapshotEvidenceLine {

    /// 把一行证据按 tag 幂等写入指定文件
    static func write(_ line: String, tag: String, fileName: String) {
        guard let path = ProcessInfo.processInfo.environment["NM_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent(fileName)
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let prefix = "[\(tag)]"
        let kept = existing.split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !$0.hasPrefix(prefix) }
        let merged = (kept + [line]).joined(separator: "\n") + "\n"
        try? merged.write(to: url, atomically: true, encoding: .utf8)
    }
}
#endif
