import Foundation

// MARK: - 卡片文本样式与断行

/// 卡片文本样式判定与断行预处理 — 纯字符串逻辑，不持有 UI 状态
///
/// 从 `ClipboardCardView` 拆出（单文件体积上限治理），供卡片视图与后续列表类视图共用。
enum ClipboardCardTextStyle {

    /// 零宽空格：提供断行机会，本身不绘制
    static let zeroWidthSpace = "\u{200B}"

    /// 断行机会字符（等宽文本在它们之后允许换行，避免 URL / 命令整段溢出）
    private static let breakOpportunities: Set<Character> = ["/", ".", "-", "_", ":", "?", "&", "=", ",", "\\"]

    /// 常见命令首词：命中即按「命令」等宽展示
    private static let commandNames: Set<String> = [
        "sudo", "git", "swift", "swiftc", "xcodebuild", "xcrun", "npm", "npx", "pnpm", "yarn", "bun",
        "brew", "docker", "kubectl", "curl", "wget", "ssh", "scp", "rsync", "make", "cmake", "cargo",
        "python", "python3", "node", "deno", "go", "java", "mvn", "gradle", "pod", "cd", "ls", "cat",
        "grep", "rg", "sed", "awk", "find", "which", "echo", "open", "defaults", "launchctl", "tar",
        "zip", "unzip", "mkdir", "cp", "mv", "rm", "chmod", "chown", "kill", "ps", "top", "df", "du"
    ]

    /// 是否按等宽展示（URL / 命令 / JSON → 12pt 等宽，其余 13pt 正文）
    static func isMonospaced(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
            || trimmed.hasPrefix("www.") || trimmed.hasPrefix("git@") { return true }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return true }
        if trimmed.hasPrefix("$ ") || trimmed.hasPrefix("./") { return true }
        let firstWord = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            .first.map(String.init) ?? trimmed
        return commandNames.contains(firstWord)
    }

    /// 断行预处理：折叠换行、在断点字符后埋零宽空格、超长无断点串按定长切分
    ///
    /// AppKit 的 `.byCharWrapping` 会在单词中间硬断，这里改用 `.byWordWrapping` 并预先埋好断点：
    /// 长 URL / 命令优先在 `/ . - _ :` 之后换行，哈希这类无断点长串才退化为定长切分。
    static func breakable(_ text: String, monospaced: Bool) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        // 等宽文本靠断点字符换行，正文只在极长单词处兜底
        let maxRun = monospaced ? 12 : 24
        var output = ""
        var run = 0
        for character in normalized {
            output.append(character)
            if monospaced, breakOpportunities.contains(character) {
                output.append(zeroWidthSpace)
                run = 0
            } else if character.isWhitespace {
                run = 0
            } else {
                run += 1
                if run >= maxRun {
                    output.append(zeroWidthSpace)
                    run = 0
                }
            }
        }
        return output
    }
}
