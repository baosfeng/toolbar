import Foundation

// MARK: - 图片文字识别的调度口径

/// 剪贴板图片文字识别的调度口径 — 纯逻辑（无 Dispatch / 无 AppKit / 无 Vision）
///
/// 三件事收在这一处，调用方与测试共用同一份判据：
/// 1. 该不该识别（开关 / 条目类型 / 路径 / 三态收敛）；
/// 2. 识别结果怎么落库（空结果写成终态空串，而不是留 NULL 让下次启动再试）；
/// 3. 失败后的冷却与次数上限（与缩略图管线同一范式，见 `ClipboardThumbnailRetryPolicy`）。
///
/// 与缩略图策略的差别只有一处：识别失败多给了「终态空串」这条出口——
/// 一个解不开的坏图不该在每次启动都被重新识别一遍。
public enum ClipboardOCRPolicy {

    /// 单条识别结果最多落库的字节数（与采集文本上限同源，避免一张大截图撑爆数据库）
    public static let maxStoredBytes = 64 * 1024

    /// 识别文本的最小可用长度：低于它视为「没认出字」，按空结果处理
    private static let minimumUsefulCharacters = 1

    // MARK: 是否识别

    /// 该条目本次是否应该进入识别队列
    ///
    /// 判据顺序（任一不满足即不识别）：开关打开 → 是图片条目 → 有落盘路径 →
    /// `ocr_text` 为 NULL（未识别）。空串是终态，正文是结果，两者都不再入队。
    /// - Parameters:
    ///   - item: 待判定的条目
    ///   - enabled: 用户设置里的「识别图片中文字」开关
    public static func shouldRecognize(_ item: ClipboardItem, enabled: Bool) -> Bool {
        guard enabled else { return false }
        guard item.kind == .image, item.ocrText == nil else { return false }
        guard let path = item.imagePath, !path.isEmpty else { return false }
        return true
    }

    // MARK: 结果收敛

    /// 把识别出的行整理成落库文本：按阅读顺序拼行 → 折叠多余空行 → 按字节上限截断
    ///
    /// 返回空串表示「确认无文字」，调用方应把它当作终态写入（不是「识别失败」）。
    /// - Parameters:
    ///   - lines: Vision 返回的识别行
    ///   - minimumConfidence: 置信度下限（低于它的行多半是背景纹理误识别）
    public static func storedText(from lines: [SnipTextLine],
                                  minimumConfidence: Double = SnipTextRecognition.defaultMinimumConfidence) -> String {
        let plain = SnipTextRecognition.plainText(from: lines, minimumConfidence: minimumConfidence)
        guard plain.count >= minimumUsefulCharacters else { return "" }
        return ClipboardContentHasher.truncate(plain, toUTF8Bytes: maxStoredBytes)
    }

    /// 面板详情区展示用文案：只去首尾空白，**保留原换行**
    ///
    /// 不折叠换行：识别结果的行结构本身就是截图里的排版，压成一段反而更难读
    /// （详情区正文按宽度自动折行，超长仍在内部滚动）。
    /// 空结果返回 nil —— 调用方据此「没有就不占位」。
    public static func displayText(for item: ClipboardItem) -> String? {
        let trimmed = item.ocrText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - 识别失败冷却

/// 图片文字识别失败的退避与终态策略 — 纯状态机（时间可注入，可直接被 TestRunner 断言）
///
/// 与 `ClipboardThumbnailRetryPolicy` 同构但**不复用**：两处的终态语义不同
/// （缩略图的终态是「本会话不再解」，识别的终态是「写一条空结果进库、以后再也不调度」），
/// 复用会把两条不同的生命周期绑在一起。
public struct ClipboardOCRRetryPolicy: Sendable {

    /// 默认冷却时长（秒）
    public static let defaultCooldown: TimeInterval = 60

    /// 默认最大尝试次数（含首次），达到后转终态
    public static let defaultMaxAttempts = 2

    /// 冷却时长（≥ 0；负数归一化为 0）
    public let cooldown: TimeInterval

    /// 最大失败次数（含首次；≤ 0 归一化为默认值）
    public let maxAttempts: Int

    /// 各条目 id 的失败记录（最近一次失败时间 + 累计次数）
    private var failures: [String: Failure] = [:]

    /// 单条失败记录
    private struct Failure {
        /// 最近一次失败时间
        var lastFailure: Date
        /// 累计失败次数
        var attempts: Int
    }

    public init(cooldown: TimeInterval = defaultCooldown, maxAttempts: Int = defaultMaxAttempts) {
        self.cooldown = cooldown > 0 ? cooldown : 0
        self.maxAttempts = maxAttempts > 0 ? maxAttempts : Self.defaultMaxAttempts
    }

    // MARK: 查询

    /// 该条目累计失败次数（未失败过为 0）
    public func failureCount(key: String) -> Int {
        failures[normalized(key)]?.attempts ?? 0
    }

    /// 该条目是否已进入终态（累计失败达上限，应写空结果、不再重试）
    public func isExhausted(key: String) -> Bool {
        failureCount(key: key) >= maxAttempts
    }

    /// 是否允许本次识别
    ///
    /// 从未失败 → true；已达 `maxAttempts` → false（终态）；冷却未过 → false；冷却已过 → true。
    public func shouldAttempt(key: String, now: Date = Date()) -> Bool {
        let key = normalized(key)
        guard !key.isEmpty else { return false }
        guard let failure = failures[key] else { return true }
        guard failure.attempts < maxAttempts else { return false }
        return now.timeIntervalSince(failure.lastFailure) >= cooldown
    }

    /// 距离下次允许识别还剩多少秒
    ///
    /// 可立即尝试（从未失败 / 冷却已过）返回 0；已进入终态返回 nil（调用方据此写空结果并停止排期）。
    public func retryDelay(key: String, now: Date = Date()) -> TimeInterval? {
        let key = normalized(key)
        guard !key.isEmpty else { return nil }
        guard let failure = failures[key] else { return 0 }
        guard failure.attempts < maxAttempts else { return nil }
        return max(0, cooldown - now.timeIntervalSince(failure.lastFailure))
    }

    // MARK: 状态变更

    /// 记录一次失败：累计次数 +1 并刷新时间戳；空白 key 无副作用
    public mutating func markFailed(key: String, now: Date = Date()) {
        let key = normalized(key)
        guard !key.isEmpty else { return }
        // 已达上限后不再累加，避免长时间运行后计数无意义地增长
        let attempts = failures[key]?.attempts ?? 0
        guard attempts < maxAttempts else { return }
        failures[key] = Failure(lastFailure: now, attempts: attempts + 1)
    }

    /// 记录一次成功：清空该条目全部失败记录
    public mutating func markSucceeded(key: String) {
        let key = normalized(key)
        guard !key.isEmpty else { return }
        failures.removeValue(forKey: key)
    }

    /// 清空全部记录（会话级重置 / 测试收尾）
    public mutating func reset() {
        failures.removeAll()
    }

    // MARK: 内部实现

    /// key 归一化：去首尾空白（空白 key 视为非法入参）
    private func normalized(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
