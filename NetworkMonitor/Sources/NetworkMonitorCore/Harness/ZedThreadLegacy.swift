import Foundation

// MARK: - Zed 旧库格式（version < 0.3.0 的 request_token_usage）

/// `threads.db` 里 `data` 的 `request_token_usage` 有两种形态：
///
/// - **旧格式**：`legacy_thread.rs` 的 `SerializedThread`（`VERSION` = 0.2.0，更老的库连
///   `version` 键都没有）—— `Vec<TokenUsage>`，**按 `messages` 下标对齐**，上游升级时对
///   assistant 消息取 `request_token_usage.get(ix)`；
/// - **新格式**：`db.rs` 的 `DbThread`（`VERSION` 0.3.0 起）—— `HashMap<ClientUserMessageId, TokenUsage>`，
///   落成 JSON 对象，键是消息 id。
///
/// 只按对象解析会让老库整段用量丢失（数组喂不进对象），故这里按顶层 `version` 分支，
/// 并用**真实形状兜底**：版本与形状不一致时按形状读，绝不把整个 thread 判成无效。
enum ZedThreadLegacy {
    /// 新格式（map）的版本下界 —— `DbThread::VERSION`
    static let mapFormatVersion = (major: 0, minor: 3, patch: 0)

    /// 顶层 `version` 是否声明了 map 形态
    ///
    /// 缺 `version` 或解析不出数字 → 视为旧格式（上游 `DbThread::from_json` 对缺失版本的库
    /// 同样走 legacy 升级路径）。
    static func prefersMap(version: String?) -> Bool {
        guard let version, let parsed = versionParts(version) else { return false }
        return parsed >= mapFormatVersion
    }

    /// 逐请求用量 + 跳过计数（字段缺失 / 类型不符 / 全零都算跳过，不整文件失败）
    ///
    /// 顺序确定：map 按键排序、旧格式按下标，同一份数据两次解析结果一致。
    static func usages(version: String?, raw: Any?) -> (usages: [HarnessTokenUsage], skipped: Int) {
        guard let raw else { return ([], 0) }
        if prefersMap(version: version) {
            if let map = raw as? [String: Any] { return mapUsages(map) }
            if let vector = raw as? [Any] { return vectorUsages(vector) }
        } else {
            if let vector = raw as? [Any] { return vectorUsages(vector) }
            if let map = raw as? [String: Any] { return mapUsages(map) }
        }
        return ([], 1)
    }

    // MARK: - 两种形态

    /// 新格式：消息 id → 用量
    private static func mapUsages(_ map: [String: Any]) -> (usages: [HarnessTokenUsage], skipped: Int) {
        var usages: [HarnessTokenUsage] = []
        var skipped = 0
        for key in map.keys.sorted() {
            guard let entry = TokenSourceJSON.object(map[key]) else {
                skipped += 1
                continue
            }
            let usage = ZedThreadParser.usage(from: entry)
            guard usage.totalTokens > 0 else {
                skipped += 1
                continue
            }
            usages.append(usage)
        }
        return (usages, skipped)
    }

    /// 旧格式：按消息下标的数组（下标本身不带信息，逐条求和即可）
    private static func vectorUsages(_ vector: [Any]) -> (usages: [HarnessTokenUsage], skipped: Int) {
        var usages: [HarnessTokenUsage] = []
        var skipped = 0
        for element in vector {
            guard let entry = TokenSourceJSON.object(element) else {
                skipped += 1
                continue
            }
            let usage = ZedThreadParser.usage(from: entry)
            guard usage.totalTokens > 0 else {
                skipped += 1
                continue
            }
            usages.append(usage)
        }
        return (usages, skipped)
    }

    /// `"0.3.0"` → `(0, 3, 0)`；主段不是数字返回 nil（`"0.3"` 按 `(0,3,0)` 处理）
    private static func versionParts(_ text: String) -> (major: Int, minor: Int, patch: Int)? {
        let pieces = text.split(separator: ".").prefix(3).map { Int($0) ?? 0 }
        guard let major = Int(text.split(separator: ".").first ?? "") else { return nil }
        return (major, pieces.count > 1 ? pieces[1] : 0, pieces.count > 2 ? pieces[2] : 0)
    }
}
