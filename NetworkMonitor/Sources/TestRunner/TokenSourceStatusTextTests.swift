import Foundation
import NetworkMonitorUI

// MARK: - 来源状态四档与文案（设计规格 §4.1）
//
// 覆盖：四档判据的边界组合（含「有 hasUsage 但零会话」这类矛盾输入）/
// 四档副标题文案 / 目录不可达但已有索引数据的保留文案 / note / canEnable / isWarning。
// 全是纯函数断言：不碰视图、不读文件系统。

func runTokenSourceStatusTextTests() {
    print("🧪 Testing 来源状态四档（判据边界 / 文案 / note / canEnable）...")

    // MARK: 四档判据：目录优先于可读，可读优先于会话数与用量
    assertEqual(TokenSourceStatusText.status(directoryExists: false, readable: false,
                                              sessionCount: 0, hasUsage: false),
                .notInstalled, "判据：目录不存在 → 灰（未安装）")
    assertEqual(TokenSourceStatusText.status(directoryExists: false, readable: true,
                                              sessionCount: 5, hasUsage: true),
                .notInstalled, "判据边界：目录不存在优先于可读 / 会话数 / 用量")
    assertEqual(TokenSourceStatusText.status(directoryExists: true, readable: false,
                                              sessionCount: 5, hasUsage: true),
                .unreadable, "判据：目录不可读 → 红（不可读优先于会话数与用量）")
    assertEqual(TokenSourceStatusText.status(directoryExists: true, readable: true,
                                              sessionCount: 0, hasUsage: false),
                .noSessions, "判据：可读但零会话 → 黄（零会话）")
    assertEqual(TokenSourceStatusText.status(directoryExists: true, readable: true,
                                              sessionCount: 0, hasUsage: true),
                .noSessions, "判据边界：零会话 + hasUsage=true 是矛盾输入，仍判黄（只看会话数）")
    assertEqual(TokenSourceStatusText.status(directoryExists: true, readable: true,
                                              sessionCount: -1, hasUsage: true),
                .noSessions, "判据边界：负会话数不算有数据 → 黄")
    assertEqual(TokenSourceStatusText.status(directoryExists: true, readable: true,
                                              sessionCount: 1, hasUsage: false),
                .noTelemetry, "判据：有会话但无用量 → 黄（无遥测）")
    assertEqual(TokenSourceStatusText.status(directoryExists: true, readable: true,
                                              sessionCount: 1, hasUsage: true),
                .ok, "判据：有会话有用量 → 绿（有数据）")
    assertEqual(TokenSourceStatusText.status(directoryExists: true, readable: true,
                                              sessionCount: 100, hasUsage: true),
                .ok, "判据：规模不影响分档")

    // MARK: 点语义：灰 / 红 / 黄 / 绿
    let installedStates: [(TokenSourceStatus, Bool)] = [
        (.notInstalled, false), (.unreadable, false), (.noSessions, true),
        (.noTelemetry, true), (.ok, false),
    ]
    for (state, warning) in installedStates {
        assertEqual(state.isWarning, warning, "点语义：\(state) isWarning = \(warning)")
    }
    let enableStates: [(TokenSourceStatus, Bool)] = [
        (.notInstalled, false), (.unreadable, true), (.noSessions, true),
        (.noTelemetry, true), (.ok, true),
    ]
    for (state, canEnable) in enableStates {
        assertEqual(state.canEnable, canEnable,
                    "可启用：\(state) canEnable = \(canEnable)（判据只看「未安装」，调用点同此）")
    }

    // MARK: 副标题四档文案
    assertEqual(TokenSourceStatusText.subtitle(path: "/Users/me/.claude/projects", status: .ok,
                                               counts: "12 会话 / 340 事件"),
                "/Users/me/.claude/projects · 目录可读 · 已索引 12 会话 / 340 事件",
                "文案：绿档带规模")
    assertEqual(TokenSourceStatusText.subtitle(path: "/Users/me/.claude/projects", status: .ok,
                                               counts: nil),
                "/Users/me/.claude/projects · 目录可读 · 有数据", "文案：绿档无规模")
    assertEqual(TokenSourceStatusText.subtitle(path: "", status: .notInstalled, counts: nil),
                "未配置目录 · 未安装（目录不存在）", "文案：灰档 + 空路径")
    assertEqual(TokenSourceStatusText.subtitle(path: "/Users/me/.codex/sessions", status: .notInstalled,
                                               counts: "3 会话 / 120 事件"),
                "/Users/me/.codex/sessions · 目录不可达，已有索引数据保留（3 会话 / 120 事件）",
                "文案：目录不可达但有索引数据 → 灰点 + 保留文案")
    assertEqual(TokenSourceStatusText.subtitle(path: "/Volumes/ext/sessions", status: .unreadable,
                                               counts: "9 会话"),
                "/Volumes/ext/sessions · 目录存在但不可读（检查权限或卷）",
                "文案：红档（规模不参与）")
    assertEqual(TokenSourceStatusText.subtitle(path: "/Users/me/.claude/projects", status: .noSessions,
                                               counts: nil),
                "/Users/me/.claude/projects · 目录存在 · 未检测到会话数据", "文案：零会话")
    assertEqual(TokenSourceStatusText.subtitle(path: "/Users/me/.claude/projects", status: .noTelemetry,
                                               counts: "4 会话"),
                "/Users/me/.claude/projects · 目录存在 · 会话里没有 token 记录（版本可能不写用量）",
                "文案：无遥测（规模不参与）")

    // MARK: 状态说明：只有 ok 不占位置
    assertEqual(TokenSourceStatusText.note(for: .ok), nil as String?, "note：绿档为 nil")
    assertEqual(TokenSourceStatusText.note(for: .notInstalled),
                "未检测到，点「选择目录…」指定可读的目录", "note：灰档给处置办法")
    assertEqual(TokenSourceStatusText.note(for: .unreadable),
                "目录存在但读不了，检查权限或卷是否已挂载", "note：红档给处置办法")
    assertEqual(TokenSourceStatusText.note(for: .noSessions),
                "目录可读，但还没有可统计的会话", "note：零会话")
    assertEqual(TokenSourceStatusText.note(for: .noTelemetry),
                "会话里没有 token 记录（该工具版本可能不写用量）", "note：无遥测")

    print("✅ 来源状态四档 works")
}
