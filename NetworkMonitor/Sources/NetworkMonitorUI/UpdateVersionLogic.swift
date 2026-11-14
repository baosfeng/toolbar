import Foundation

// MARK: - 语义化版本

/// 语义化版本 — 版本号解析与比较的唯一口径
///
/// 为什么不能拿字符串直接比：字典序下 `"1.24.9" > "1.24.10"`，会把「9 修订」判成比「10 修订」新，
/// 界面就会一直提示有更新（或永远不提示）。所以比较一律按「主 → 次 → 修订 → 预发布」四段数值走。
///
/// 可识别的写法（GitHub tag 的实际形态）：
/// - `1.24.10` / `v1.24.10`（tag 前缀 `v` / `V` 容忍）
/// - `1.24.3-beta.1`（预发布后缀，按语义化版本规范第 11 条比较）
/// - `1.24.10+build.7`（构建元数据不参与比较）
public struct UpdateVersion: Equatable, Comparable, Sendable {

    public let major: Int
    public let minor: Int
    public let patch: Int
    /// 预发布标识（空数组 = 正式版）：`1.24.3-beta.1` → `["beta", "1"]`
    public let prerelease: [String]

    public init(major: Int, minor: Int, patch: Int, prerelease: [String] = []) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    /// 是否预发布
    public var isPrerelease: Bool { !prerelease.isEmpty }

    /// 展示文本（保留预发布后缀，「最新版本」行直接用它）
    public var displayText: String {
        let core = "\(major).\(minor).\(patch)"
        guard isPrerelease else { return core }
        return core + "-" + prerelease.joined(separator: ".")
    }

    public static func < (lhs: UpdateVersion, rhs: UpdateVersion) -> Bool {
        compare(lhs, rhs) < 0
    }

    /// 三段式比较：`-1` 小于 / `0` 相等 / `1` 大于
    public static func compare(_ lhs: UpdateVersion, _ rhs: UpdateVersion) -> Int {
        if lhs.major != rhs.major { return lhs.major < rhs.major ? -1 : 1 }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor ? -1 : 1 }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch ? -1 : 1 }
        return comparePrerelease(lhs.prerelease, rhs.prerelease)
    }

    /// 预发布比较（语义化版本规范第 11 条）
    ///
    /// 三条规则：正式版大于任何预发布；数字标识符小于字母标识符；前缀相同则标识符少的更小。
    private static func comparePrerelease(_ lhs: [String], _ rhs: [String]) -> Int {
        if lhs.isEmpty && rhs.isEmpty { return 0 }
        // 1.24.3 正式版 > 1.24.3-beta.1
        if lhs.isEmpty { return 1 }
        if rhs.isEmpty { return -1 }
        for (left, right) in zip(lhs, rhs) {
            if left == right { continue }
            switch (Int(left), Int(right)) {
            case let (leftNumber?, rightNumber?):
                return leftNumber < rightNumber ? -1 : 1
            case (.some, .none):
                return -1
            case (.none, .some):
                return 1
            case (.none, .none):
                return left < right ? -1 : 1
            }
        }
        if lhs.count == rhs.count { return 0 }
        return lhs.count < rhs.count ? -1 : 1
    }
}

// MARK: - 解析失败

/// 版本号解析失败 — 明确说出哪一段不对，界面据此显示「无法检查（原因）」
///
/// 不用 `nil` 表达失败：调用方没法区分「没解析」与「解析成 0.0.0」，
/// 静默当 0 会让任何字符串都被判成「有更新」。
public enum UpdateVersionParseError: Error, Equatable, Sendable {
    /// 空串 / 全空白
    case empty
    /// 不是「主.次.修订」三段（只有一段 / 两段 / 四段）
    case notThreeSegments(String)
    /// 某一段不是非负整数
    case nonNumeric(String)

    /// 面向用户的中文原因
    public var message: String {
        switch self {
        case .empty:
            return "版本号为空"
        case .notThreeSegments(let raw):
            return "版本号不是「主.次.修订」三段：\(raw)"
        case .nonNumeric(let segment):
            return "版本号含非数字段：\(segment)"
        }
    }
}

// MARK: - 解析与判定

/// 版本口径入口 — 解析、tag 提取、「是否比当前新」
public enum UpdateVersionLogic {

    /// 解析版本号（容忍 `v` / `V` 前缀、前后空白、`+构建元数据`）
    public static func parse(_ raw: String) -> Result<UpdateVersion, UpdateVersionParseError> {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure(.empty) }
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        // 构建元数据（+build.7）不参与比较，直接丢掉
        if let plus = text.firstIndex(of: "+") {
            text = String(text[text.startIndex..<plus])
        }
        // 预发布后缀从第一个「-」开始（版本号本身不会出现「-」）
        var prerelease: [String] = []
        if let dash = text.firstIndex(of: "-") {
            let suffix = text[text.index(after: dash)...]
            prerelease = suffix.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            text = String(text[text.startIndex..<dash])
        }
        let segments = text.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard segments.count == 3 else { return .failure(.notThreeSegments(raw)) }
        var numbers: [Int] = []
        for segment in segments {
            guard !segment.isEmpty, let value = Int(segment), value >= 0 else {
                return .failure(.nonNumeric(segment.isEmpty ? text : segment))
            }
            numbers.append(value)
        }
        return .success(UpdateVersion(major: numbers[0], minor: numbers[1], patch: numbers[2],
                                      prerelease: prerelease))
    }

    /// 从 GitHub tag / tag_name 提取版本（`v1.24.10` 与 `1.24.10` 同义）
    public static func version(fromTag tag: String) -> Result<UpdateVersion, UpdateVersionParseError> {
        parse(tag)
    }

    /// 最新版本是否比当前版本新
    ///
    /// 任一版本号解析失败返回 `nil`：调用方必须按「无法比较」处理，
    /// 不能把解析失败当作「没有更新」（那会把真实的更新静默吞掉）。
    public static func isUpdateAvailable(current: String, latest: String) -> Bool? {
        guard case .success(let currentVersion) = parse(current),
              case .success(let latestVersion) = parse(latest) else { return nil }
        return latestVersion > currentVersion
    }
}
