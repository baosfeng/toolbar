import Foundation

// MARK: - 来源标识

/// 多来源 token 用量的来源标识
///
/// rawValue 是**落库标识**（`harness_token_event.source` / `harness_session_scan.source`）
/// 与偏好键的一部分（`token.source.<id>.rootPath`）：一旦发布就不可再改，
/// 新增来源只能追加 case。老数据靠 `ALTER TABLE ... DEFAULT 'dsh'` 归到 `.dsh`。
public enum TokenSourceID: String, Sendable, Equatable, CaseIterable, Codable {
    /// DSH（DeepSeek Harness）—— 既有链路，也是老数据的默认值
    case dsh = "dsh"
    /// Claude Code（`~/.claude/projects` 下的 transcript JSONL）
    case claudeCode = "claude-code"
    /// Codex CLI（`$CODEX_HOME/sessions` 下的 rollout JSONL）
    case codex = "codex"
    /// Gemini CLI
    case gemini = "gemini"
    /// Copilot CLI
    case copilot = "copilot"
    /// OpenCode
    case opencode = "opencode"
    /// Zed
    case zed = "zed"

    /// 老数据缺省来源（与建表 `DEFAULT 'dsh'` 必须同源，改一处要同时改另一处）
    public static let legacy: TokenSourceID = .dsh

    /// 展示名（面板页头 / 设置页来源清单）
    public var displayName: String {
        switch self {
        case .dsh: return "DSH"
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .gemini: return "Gemini CLI"
        case .copilot: return "Copilot CLI"
        case .opencode: return "OpenCode"
        case .zed: return "Zed"
        }
    }

    /// 该来源识别的环境变量（nil = 无环境变量覆盖，只认 home 下的默认路径）
    public var environmentKey: String? {
        switch self {
        case .dsh: return "DSH_HOME"
        case .claudeCode: return "CLAUDE_CONFIG_DIR"
        case .codex: return "CODEX_HOME"
        case .gemini: return "GEMINI_CLI_HOME"
        case .copilot: return nil
        case .opencode: return "XDG_DATA_HOME"
        case .zed: return nil
        }
    }

    /// 默认根目录（按优先级排列）
    ///
    /// 只做**路径推导**，不判断存在性与可读性 —— 那是扫描器的事，两件事分开才能让
    /// 「未安装 / 装了但没数据 / 不可读」在界面上说清。
    /// 环境变量给了就只用环境变量给出的根；没给才回落到 home 下的固定位置。
    public func defaultRoots(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [URL] {
        let env = TokenSourceEnvironment(values: environment)
        switch self {
        case .dsh:
            if let dshHome = env.path("DSH_HOME") {
                return [dshHome.appendingPathComponent("sessions", isDirectory: true)]
            }
            return [home(homeDirectory, ".dsh").appendingPathComponent("sessions", isDirectory: true)]
        case .claudeCode:
            // CLAUDE_CONFIG_DIR 支持逗号分隔多根，其下的 projects 才是 transcript 目录
            let configDirs = env.pathList("CLAUDE_CONFIG_DIR")
            if !configDirs.isEmpty {
                return configDirs.map { $0.appendingPathComponent("projects", isDirectory: true) }
            }
            return [
                home(homeDirectory, ".claude").appendingPathComponent("projects", isDirectory: true),
                home(homeDirectory, ".config").appendingPathComponent("claude", isDirectory: true)
                    .appendingPathComponent("projects", isDirectory: true),
            ]
        case .codex:
            // 同一会话可能同时存在于 sessions/ 与 archived_sessions/，两个根都给出
            let base = env.path("CODEX_HOME") ?? home(homeDirectory, ".codex")
            return [
                base.appendingPathComponent("sessions", isDirectory: true),
                base.appendingPathComponent("archived_sessions", isDirectory: true),
            ]
        case .gemini:
            if let base = env.path("GEMINI_CLI_HOME") {
                return [base.appendingPathComponent(".gemini", isDirectory: true)]
            }
            return [home(homeDirectory, ".gemini")]
        case .copilot:
            return [home(homeDirectory, ".copilot")]
        case .opencode:
            let base = env.path("XDG_DATA_HOME")
                ?? home(homeDirectory, ".local").appendingPathComponent("share", isDirectory: true)
            return [base.appendingPathComponent("opencode", isDirectory: true)]
        case .zed:
            return [
                home(homeDirectory, "Library")
                    .appendingPathComponent("Application Support", isDirectory: true)
                    .appendingPathComponent("Zed", isDirectory: true)
                    .appendingPathComponent("threads", isDirectory: true),
            ]
        }
    }

    /// home 下的第一级目录
    private func home(_ homeDirectory: URL, _ component: String) -> URL {
        homeDirectory.appendingPathComponent(component, isDirectory: true)
    }
}

// MARK: - 环境变量读取

/// 环境变量读取（去空白 + 展开 `~`，环境字典可注入以便测试与设置页预览）
struct TokenSourceEnvironment {
    let values: [String: String]

    /// 单值路径；空白字符串视同未设置
    func path(_ key: String) -> URL? {
        guard let raw = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: expandTilde(raw), isDirectory: true)
    }

    /// 逗号分隔的多值路径（Claude 的 `CLAUDE_CONFIG_DIR` 支持多根）
    func pathList(_ key: String) -> [URL] {
        guard let raw = values[key], !raw.isEmpty else { return [] }
        return raw.split(separator: ",").compactMap { piece in
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return URL(fileURLWithPath: expandTilde(trimmed), isDirectory: true)
        }
    }

    /// 展开开头的 `~`（环境变量里写 `~/.claude` 很常见）
    private func expandTilde(_ path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        return (path as NSString).expandingTildeInPath
    }
}
