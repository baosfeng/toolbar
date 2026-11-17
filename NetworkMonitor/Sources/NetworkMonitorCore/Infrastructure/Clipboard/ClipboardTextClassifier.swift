import Foundation

// MARK: - 文本内容类型

/// 剪贴板文本条目的内容类型 —— 只描述「这段文本像什么」
///
/// 刻意不改 `ClipboardItemKind`：那是落库字段，改它会牵涉旧数据兼容读。
/// 本类型只服务展示口径（类型标签 / 卡片图标），不参与存储。
public enum ClipboardTextKind: String, CaseIterable, Sendable {
    /// 链接（http(s):// 或 www. 开头，单行）
    case url
    /// 邮箱地址（单行）
    case email
    /// 颜色字面量（#hex 或 rgb()/rgba()/hsl()/hsla()）
    case color
    /// JSON 对象或数组（唯一允许跨行的类型）
    case json
    /// 命令（常见 shell 前缀，单行）
    case command
    /// 其余纯文本
    case plain
}

// MARK: - 判定依据

/// 判定依据 —— 让「为什么判成这个」可被测试断言，而不是靠注释口口相传
public enum ClipboardTextEvidence: String, Sendable {
    /// http:// 或 https:// 开头
    case schemeURL
    /// www. 开头
    case wwwPrefix
    /// 单行、含 @ 且域名带点
    case mailAddress
    /// #FFF / #RGBA / #RRGGBB / #RRGGBBAA
    case hexColor
    /// rgb() / rgba() / hsl() / hsla()
    case functionalColor
    /// 能解析且顶层是对象或数组
    case parseableJSON
    /// 常见 shell 命令前缀
    case shellCommand
    /// 未命中任何特征（含空串、多行、纯数字）
    case none
}

/// 判定结果（类型 + 依据）
public struct ClipboardTextClassification: Equatable, Sendable {
    /// 内容类型
    public let kind: ClipboardTextKind
    /// 判定依据
    public let evidence: ClipboardTextEvidence

    public init(kind: ClipboardTextKind, evidence: ClipboardTextEvidence) {
        self.kind = kind
        self.evidence = evidence
    }

    /// 未命中任何特征
    public static let plain = ClipboardTextClassification(kind: .plain, evidence: .none)
}

// MARK: - 文本类型判定

/// 剪贴板文本类型判定 —— 纯函数、无 AppKit、可被 TestRunner 直接断言
///
/// 类型标签（`ClipboardItemKindLabel`）与卡片图标（`ClipboardCardView.symbolName`）
/// 都由这一处判定，避免「同一条目在不同位置显示不同类型」。
///
/// 判定顺序（先强特征后弱特征，任一步命中即返回）：
/// 1. 空 / 纯空白 → plain
/// 2. JSON：首字符是 `{` 或 `[` 且能解析成对象 / 数组 → json（唯一允许跨行的类型）
/// 3. 跨行文本 → plain（URL / 邮箱 / 颜色 / 命令都要求单行）
/// 4. 纯数字 → plain（验证码、235442 这类不得变成色块）
/// 5. http(s):// → url；www. → url
/// 6. `#` + 3/4/6/8 位 hex，或 rgb()/rgba()/hsl()/hsla() → color
/// 7. 单行、含 @ 且域名带点 → email
/// 8. 常见 shell 前缀或 `$ ` / `./` 开头 → command
/// 9. 其余 → plain
public enum ClipboardTextClassifier {

    /// 尝试 JSON 解析的字符数上限：超过就直接判 plain
    ///
    /// 超长文本里 JSON 解析是本次唯一的 O(n) 重活；粘贴 1MB 文本不该为判定付这份钱。
    public static let jsonProbeLimit = 64 * 1024

    /// 常见命令首词（与卡片等宽展示口径同批词，同一条文本不该在两处被判成不同东西）
    private static let commandNames: Set<String> = [
        "sudo", "git", "swift", "swiftc", "xcodebuild", "xcrun", "npm", "npx", "pnpm", "yarn", "bun",
        "brew", "docker", "kubectl", "curl", "wget", "ssh", "scp", "rsync", "make", "cmake", "cargo",
        "python", "python3", "node", "deno", "go", "java", "mvn", "gradle", "pod", "cd", "ls", "cat",
        "grep", "rg", "sed", "awk", "find", "which", "echo", "open", "defaults", "launchctl", "tar",
        "zip", "unzip", "mkdir", "cp", "mv", "rm", "chmod", "chown", "kill", "ps", "top", "df", "du"
    ]

    /// 判定入口
    /// - Parameter text: 原始文本（首尾空白会被忽略）
    /// - Returns: 类型与判定依据；空串与纯空白返回 `.plain`
    public static func classify(_ text: String) -> ClipboardTextClassification {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .plain }
        if let json = jsonClassification(trimmed) { return json }
        guard !trimmed.contains(where: { $0.isNewline }) else { return .plain }
        guard !isAllDigits(trimmed) else { return .plain }
        if let url = urlClassification(trimmed) { return url }
        if let color = colorClassification(trimmed) { return color }
        if looksLikeEmail(trimmed) {
            return ClipboardTextClassification(kind: .email, evidence: .mailAddress)
        }
        if looksLikeCommand(trimmed) {
            return ClipboardTextClassification(kind: .command, evidence: .shellCommand)
        }
        return .plain
    }

    // MARK: - 各类型判定

    /// JSON：只对 `{` / `[` 开头且不超长的文本尝试解析，避免对普通文本白跑一次解析
    private static func jsonClassification(_ trimmed: String) -> ClipboardTextClassification? {
        guard let first = trimmed.first, first == "{" || first == "[" else { return nil }
        guard trimmed.utf8.count <= jsonProbeLimit else { return .plain }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        guard object is [String: Any] || object is [Any] else { return nil }
        return ClipboardTextClassification(kind: .json, evidence: .parseableJSON)
    }

    /// URL：scheme 大小写不敏感，只比较前缀（不给整串做小写化）
    private static func urlClassification(_ trimmed: String) -> ClipboardTextClassification? {
        let head = String(trimmed.prefix(8)).lowercased()
        if head.hasPrefix("http://") || head.hasPrefix("https://") {
            return ClipboardTextClassification(kind: .url, evidence: .schemeURL)
        }
        if head.hasPrefix("www.") {
            return ClipboardTextClassification(kind: .url, evidence: .wwwPrefix)
        }
        return nil
    }

    /// 颜色：必须「像颜色」——带 `#` 的 hex，或函数式写法；裸数字在上面已被拦成 plain
    private static func colorClassification(_ trimmed: String) -> ClipboardTextClassification? {
        if trimmed.hasPrefix("#") {
            let body = trimmed.dropFirst()
            let hexLengths = [3, 4, 6, 8]
            if hexLengths.contains(body.count), body.allSatisfy({ $0.isHexDigit }) {
                return ClipboardTextClassification(kind: .color, evidence: .hexColor)
            }
        }
        let head = String(trimmed.prefix(5)).lowercased()
        let functionalPrefixes = ["rgb(", "rgba(", "hsl(", "hsla("]
        if functionalPrefixes.contains(where: head.hasPrefix) {
            return ClipboardTextClassification(kind: .color, evidence: .functionalColor)
        }
        return nil
    }

    /// 邮箱：单行、恰好一个 @、域名带点且顶级域至少两位字母
    ///
    /// 不接受 `:` `/` 等字符，`git@github.com:foo/bar.git` 这类 ssh 地址因此不会被误判成邮箱。
    private static func looksLikeEmail(_ text: String) -> Bool {
        guard text.utf8.count <= 320, !text.contains(where: \.isWhitespace) else { return false }
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let local = parts[0]
        let host = parts[1]
        let localAllowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._%+-")
        guard local.allSatisfy(localAllowed.contains) else { return false }
        let hostAllowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        guard host.allSatisfy(hostAllowed.contains) else { return false }
        guard host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else { return false }
        guard let tld = host.split(separator: ".").last, tld.count >= 2, tld.allSatisfy({ $0.isLetter }) else {
            return false
        }
        return true
    }

    /// 命令：`$ ` / `./` 开头，或首词在常见命令白名单里（先小写再比）
    private static func looksLikeCommand(_ text: String) -> Bool {
        if text.hasPrefix("$ ") || text.hasPrefix("./") { return true }
        let firstWord = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            .first.map(String.init) ?? text
        return commandNames.contains(firstWord.lowercased())
    }

    /// 纯 ASCII 数字：`235442` 这类验证码不得被判成颜色
    private static func isAllDigits(_ text: String) -> Bool {
        text.allSatisfy { $0 >= "0" && $0 <= "9" }
    }
}
