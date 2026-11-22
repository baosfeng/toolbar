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

    /// 该来源的会话单位是否落在 SQLite 数据库里（Copilot / OpenCode / Zed）
    ///
    /// 这个维度决定三件事，全部只读它、不在别处再散 if：
    /// 1. **发现判据**是 db 文件存在性（不是目录）；
    /// 2. **rootPath 语义**是 db 文件路径（设置页文案写「数据库文件」而不是「目录」）；
    /// 3. **会话单位**是库里的一行 message / 一个 thread，scan 记录键要拼成
    ///    `<dbPath>#<sessionKey>` 才唯一（db 的 size/mtime 仍是增量判据）。
    public var isSQLite: Bool {
        switch self {
        case .copilot, .opencode, .zed: return true
        case .dsh, .claudeCode, .codex, .gemini: return false
        }
    }

    /// 该来源识别的环境变量（nil = 无环境变量覆盖，只认 home 下的默认路径）
    public var environmentKey: String? {
        switch self {
        case .dsh: return "DSH_HOME"
        case .claudeCode: return "CLAUDE_CONFIG_DIR"
        case .codex: return "CODEX_HOME"
        case .gemini: return "GEMINI_CLI_HOME"
        case .copilot: return "COPILOT_HOME"
        // OpenCode 的官方覆盖变量是「库文件路径」（不是目录），XDG 只是默认根的推导依据
        case .opencode: return OpenCodeDatabaseLocation.environmentKey
        case .zed: return nil
        }
    }

    /// 默认根目录（按优先级排列）
    ///
    /// 只做**路径推导**，不判断存在性与可读性 —— 那是扫描器的事，两件事分开才能让
    /// 「未安装 / 装了但没数据 / 不可读」在界面上说清。
    /// 环境变量给了就只用环境变量给出的根；没给才回落到 home 下的固定位置。
    ///
    /// 唯一例外是 **OpenCode**：库名可能带渠道后缀（`opencode-<channel>.db`），后缀无从推导、
    /// 只能看目录，那一条委托给 `OpenCodeDatabaseLocation.resolve`（存在性只用于「选哪个候选」，
    /// 不可读仍由读取器报原因）。
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
            // 会话在 <home>/.gemini/tmp/<项目 slug>/chats/session-*.jsonl（旧版同目录的整份 .json）。
            // GEMINI_CLI_HOME 是「home」语义：它的下面还要再找一层 .gemini，不是直接指向 .gemini。
            let base = env.path("GEMINI_CLI_HOME") ?? homeDirectory
            return [base.appendingPathComponent(".gemini", isDirectory: true)
                .appendingPathComponent("tmp", isDirectory: true)]
        case .copilot:
            // SQLite 源：给的是 db 文件本身，不是目录。
            // 官方 JS 的 pathResolvedSessionsHome(configDir, process.env.COPILOT_HOME, homeDir)
            // 口径 = COPILOT_HOME 优先，其次 ~/.copilot（db 始终直接落在该「sessions home」下）
            let base = env.path("COPILOT_HOME") ?? home(homeDirectory, ".copilot")
            return [base.appendingPathComponent(CopilotUsageParser.databaseFileName)]
        case .opencode:
            // 三种变异（OPENCODE_DB / XDG / 渠道后缀库）的解析集中在 OpenCodeDatabaseLocation
            return [OpenCodeDatabaseLocation.resolve(
                homeDirectory: homeDirectory, environment: environment).url]
        case .zed:
            return [
                home(homeDirectory, "Library")
                    .appendingPathComponent("Application Support", isDirectory: true)
                    .appendingPathComponent("Zed", isDirectory: true)
                    .appendingPathComponent("threads", isDirectory: true)
                    .appendingPathComponent("threads.db"),
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
