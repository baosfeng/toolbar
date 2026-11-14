import Foundation

// MARK: - 更新检查状态

/// 更新检查状态 — 界面只用这一个状态源，不各自记录 bool
///
/// 五个状态互斥：`idle`（从未检查）/ `checking`（请求在途）/
/// `upToDate`（已是最新）/ `available`（有新版本）/ `failed`（查不到）。
/// 失败不是弹窗事件：只落在状态里，界面显示一行「无法检查（原因）」，不打断用户。
public enum UpdateCheckState: Equatable, Sendable {
    /// 尚未检查过
    case idle
    /// 正在检查
    case checking
    /// 已是最新（latest = 远端版本展示文本）
    case upToDate(latest: String)
    /// 有新版本（notes = 已截断的发布说明摘要）
    case available(latest: String, notes: String)
    /// 检查失败（reason = 面向用户的短原因）
    case failed(reason: String)
}

// MARK: - 状态到界面的派生

/// 关于页「检查更新」区的四行文案与按钮状态 — 由状态 + 上次检查时间一次算出
///
/// 抽成纯值是为了可断言：状态机与文案拼接都不依赖 AppKit，TestRunner 能直接覆盖
/// 「从未检查 / 正在检查 / 已是最新 / 有新版本 / 失败」五种形态。
public struct UpdateCheckPresentation: Equatable, Sendable {
    /// 「最新版本」行的值（idle / failed → 占位破折号）
    public let latestVersionText: String
    /// 「状态」行文案
    public let statusText: String
    /// 「新版本说明」行文案（无更新 → 占位破折号）
    public let notesText: String
    /// 检查按钮可否点击（请求在途时置灰，避免重复打接口）
    public let canCheck: Bool
    /// 检查按钮标题（在途时改「检查中…」，失败后改「重试」）
    public let checkButtonTitle: String
    /// 「最新版本」是否用强调色（只在发现新版本时提亮）
    public let highlightsLatest: Bool
}

/// 状态派生入口
public enum UpdateCheckText {

    /// 占位值 — 与「版本 / 构建号」行未打包时的降级一致
    public static let placeholder = "—"

    /// 按状态与上次检查时间生成四行文案
    public static func presentation(for state: UpdateCheckState,
                                    lastCheckAt: Date?,
                                    now: Date = Date()) -> UpdateCheckPresentation {
        switch state {
        case .idle:
            // 本次启动还没查过：上次查过的话把时间带上，否则用户会以为「从没查过」
            let idleStatus = lastCheckAt == nil
                ? "尚未检查"
                : "尚未检查 · " + checkedText(lastCheckAt, now: now)
            return UpdateCheckPresentation(latestVersionText: placeholder,
                                           statusText: idleStatus,
                                           notesText: placeholder,
                                           canCheck: true,
                                           checkButtonTitle: "检查更新",
                                           highlightsLatest: false)
        case .checking:
            return UpdateCheckPresentation(latestVersionText: placeholder,
                                           statusText: "正在检查…",
                                           notesText: placeholder,
                                           canCheck: false,
                                           checkButtonTitle: "检查中…",
                                           highlightsLatest: false)
        case .upToDate(let latest):
            return UpdateCheckPresentation(latestVersionText: latest,
                                           statusText: "已是最新版本 · " + checkedText(lastCheckAt, now: now),
                                           notesText: placeholder,
                                           canCheck: true,
                                           checkButtonTitle: "检查更新",
                                           highlightsLatest: false)
        case .available(let latest, let notes):
            return UpdateCheckPresentation(latestVersionText: latest,
                                           statusText: "发现新版本 · " + checkedText(lastCheckAt, now: now),
                                           notesText: notes.isEmpty ? placeholder : notes,
                                           canCheck: true,
                                           checkButtonTitle: "检查更新",
                                           highlightsLatest: true)
        case .failed(let reason):
            return UpdateCheckPresentation(latestVersionText: placeholder,
                                           statusText: "无法检查（" + reason + "）",
                                           notesText: placeholder,
                                           canCheck: true,
                                           checkButtonTitle: "重试",
                                           highlightsLatest: false)
        }
    }

    /// 「上次检查 …」短语（状态进入 upToDate / available 时必然已记录时间）
    private static func checkedText(_ lastCheckAt: Date?, now: Date) -> String {
        guard let lastCheckAt else { return "上次检查时间未知" }
        return "上次检查 " + UpdateRelativeTime.describe(since: lastCheckAt, now: now)
    }
}

// MARK: - 相对时间

/// 相对时间文案 — 「上次检查 N 分钟前」的唯一口径
///
/// 只做粗粒度分档（刚刚 / 分钟 / 小时 / 天）：更新检查是低频动作，
/// 精确到秒没有意义，反而让文案在每次刷新时抖动。
public enum UpdateRelativeTime {

    /// 距今多久（`nil` = 从未检查）
    public static func describe(since date: Date?, now: Date = Date()) -> String {
        guard let date else { return "从未" }
        let seconds = now.timeIntervalSince(date)
        // 时钟回拨 / 未来时间戳：按「刚刚」处理，不显示负分钟数
        guard seconds.isFinite, seconds >= 0 else { return "刚刚" }
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(Int(seconds / 60)) 分钟前" }
        if seconds < 86400 { return "\(Int(seconds / 3600)) 小时前" }
        return "\(Int(seconds / 86400)) 天前"
    }
}

// MARK: - 自动检查节奏

/// 自动检查节奏 — 启动后最多每 24 小时自动查一次，手动检查不受此限
public enum UpdateCheckCadence {

    /// 自动检查最小间隔（24 小时）
    public static let autoCheckInterval: TimeInterval = 24 * 60 * 60

    /// 是否已到自动检查时间（从未检查 → 立即检查）
    ///
    /// 判据写在这里而不是服务里，是因为「限频对不对」只能靠纯函数断言：
    /// 真机跑 24 小时不现实，漏判却会让每次启动都打一次 GitHub 接口。
    public static func isAutoCheckDue(lastCheckAt: Date?, now: Date = Date()) -> Bool {
        guard let lastCheckAt else { return true }
        return now.timeIntervalSince(lastCheckAt) >= autoCheckInterval
    }
}

// MARK: - 发布说明摘要

/// 发布说明摘要 — release body 压成一行并截断
///
/// 关于页那一行只有三行高，GitHub 的 release body 常是几十行 markdown：
/// 原样塞进去会把整张卡撑成半屏，所以先压空白再截断。
public enum UpdateNotes {

    /// 摘要最大字符数（三行 11pt 文案的实测容量留了余量）
    public static let summaryLimit = 160

    /// 压缩空白、剥掉行首 markdown 标记并截断（超长补省略号）
    ///
    /// 剥标记是为了界面干净：GitHub 的 body 常以 `## 更新内容` / `- 修复…` / `> 注意` 开头，
    /// 原样塞进「新版本说明」行会出现一堆 `##`，用户读到的第一眼是符号而不是内容。
    public static func summary(_ raw: String, limit: Int = summaryLimit) -> String {
        let lines = raw.split(whereSeparator: { $0.isNewline })
            .map(cleanedLine)
            .filter { !$0.isEmpty }
        let compact = lines.joined(separator: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard limit > 0, compact.count > limit else { return compact }
        return String(compact.prefix(limit)) + "…"
    }

    /// 去掉一行开头的 markdown 标记（`#` / `>` / `-` / `*` / `•`）与两侧空白
    private static func cleanedLine(_ line: Substring) -> String {
        let markers: Set<Character> = ["#", ">", "-", "*", "•"]
        var text = line.trimmingCharacters(in: .whitespaces)
        while let first = text.first, markers.contains(first) {
            text.removeFirst()
            text = text.trimmingCharacters(in: .whitespaces)
        }
        return text
    }
}
