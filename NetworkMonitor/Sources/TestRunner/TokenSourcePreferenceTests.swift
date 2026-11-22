import Foundation
import NetworkMonitorCore

// MARK: - 多来源偏好键（token.*）
//
// 覆盖：token.* 键读写往返 / dsh 源 rootPath 回落旧键 harness.sessionsRootPath /
// autoIndexEnabled 缺键 = false / autoIndexInterval 缺键 = 300 与读侧归一 / 选中来源往返。
// 全部走内存存储（InMemoryStorage）：不污染本机偏好。

func runTokenSourcePreferenceTests() {
    print("🧪 Testing 多来源偏好键（键名 / 往返 / 回落 / 缺键默认）...")

    // 键名是发布后不可改的落库标识，这里把字面量钉死
    assertEqual(TokenSourcePreferences.enabledKey(for: .claudeCode), "token.source.claude-code.enabled",
                "键名：启用开关")
    assertEqual(TokenSourcePreferences.rootPathKey(for: .codex), "token.source.codex.rootPath",
                "键名：自定义根目录")
    assertEqual(TokenSourcePreferences.selectedSourceKey, "token.selectedSource", "键名：当前来源")
    assertEqual(TokenSourcePreferences.autoIndexEnabledKey, "token.autoIndex.enabled", "键名：自动监控开关")
    assertEqual(TokenSourcePreferences.autoIndexIntervalKey, "token.autoIndex.interval", "键名：自动监控间隔")

    // MARK: 启用开关：dsh 缺键即开、其余缺键即关，显式值不被默认值翻转
    let storage = InMemoryStorage()
    assertEqual(TokenSourcePreferences.isEnabled(.dsh, storage: storage), true, "缺键：dsh 默认开")
    assertEqual(TokenSourcePreferences.isEnabled(.claudeCode, storage: storage), false, "缺键：claudeCode 默认关")
    assertEqual(TokenSourcePreferences.isEnabled(.gemini, storage: storage), false, "缺键：未接来源默认关")
    assertEqual(TokenSourcePreferences.enabledSources(storage), [TokenSourceID.dsh], "缺键：只有 dsh 启用")
    TokenSourcePreferences.setEnabled(false, for: .dsh, storage: storage)
    assertEqual(TokenSourcePreferences.isEnabled(.dsh, storage: storage), false, "显式关：覆盖 dsh 默认开")
    TokenSourcePreferences.setEnabled(true, for: .claudeCode, storage: storage)
    assertEqual(TokenSourcePreferences.isEnabled(.claudeCode, storage: storage), true, "显式开：往返")
    assertEqual(TokenSourcePreferences.enabledSources(storage), [TokenSourceID.claudeCode],
                "enabledSources：按 allCases 顺序只列启用项")

    // MARK: 根目录：token.* 往返 + 空白视同未设置
    let pathStorage = InMemoryStorage()
    assertEqual(TokenSourcePreferences.rootPath(.claudeCode, storage: pathStorage), nil, "根目录：缺键为 nil")
    TokenSourcePreferences.setRootPath("/tmp/claude-projects", for: .claudeCode, storage: pathStorage)
    assertEqual(TokenSourcePreferences.rootPath(.claudeCode, storage: pathStorage), "/tmp/claude-projects",
                "根目录：写入后可读回")
    TokenSourcePreferences.setRootPath("   ", for: .claudeCode, storage: pathStorage)
    assertEqual(TokenSourcePreferences.rootPath(.claudeCode, storage: pathStorage), nil,
                "根目录：空白视同未设置（删键）")

    // dsh 源：新键缺省时回落旧键（老用户零迁移），新键存在时新键优先
    let legacyStorage = InMemoryStorage()
    legacyStorage.set("/legacy/dsh-sessions", forKey: HarnessSourceDirectory.key)
    assertEqual(TokenSourcePreferences.rootPath(.dsh, storage: legacyStorage), "/legacy/dsh-sessions",
                "回落：dsh 读旧键 harness.sessionsRootPath")
    assertEqual(TokenSourcePreferences.rootPath(.codex, storage: legacyStorage), nil,
                "回落：其它来源不读旧键")
    TokenSourcePreferences.setRootPath("/new/dsh-sessions", for: .dsh, storage: legacyStorage)
    assertEqual(TokenSourcePreferences.rootPath(.dsh, storage: legacyStorage), "/new/dsh-sessions",
                "优先：新键覆盖旧键")
    TokenSourcePreferences.setRootPath(nil, for: .dsh, storage: legacyStorage)
    assertEqual(TokenSourcePreferences.rootPath(.dsh, storage: legacyStorage), "/legacy/dsh-sessions",
                "删新键：重新回落旧键")
    assertEqual(legacyStorage.string(forKey: HarnessSourceDirectory.key), "/legacy/dsh-sessions",
                "删新键：不动旧键（配置不凭空消失）")

    // MARK: 选中来源：nil = 删键（缺省即全部）
    let selectionStorage = InMemoryStorage()
    assertEqual(TokenSourcePreferences.selectedSource(selectionStorage), nil, "当前来源：缺键为 nil（全部）")
    TokenSourcePreferences.setSelectedSource(.codex, storage: selectionStorage)
    assertEqual(TokenSourcePreferences.selectedSource(selectionStorage), TokenSourceID.codex, "当前来源：往返")
    selectionStorage.set("not-a-source", forKey: TokenSourcePreferences.selectedSourceKey)
    assertEqual(TokenSourcePreferences.selectedSource(selectionStorage), nil, "当前来源：不认识的 rawValue 按全部")
    TokenSourcePreferences.setSelectedSource(nil, storage: selectionStorage)
    assertEqual(selectionStorage.object(forKey: TokenSourcePreferences.selectedSourceKey) == nil, true,
                "当前来源：写 nil 是删键而不是存字符串")

    // MARK: 自动监控：缺键 = 关 / 间隔缺键 = 300
    let autoStorage = InMemoryStorage()
    assertEqual(TokenSourcePreferences.autoIndexEnabled(autoStorage), false, "自动监控：缺键即关")
    TokenSourcePreferences.setAutoIndexEnabled(true, storage: autoStorage)
    assertEqual(TokenSourcePreferences.autoIndexEnabled(autoStorage), true, "自动监控：开关往返")
    assertEqual(TokenSourcePreferences.autoIndexInterval(autoStorage), 300, "间隔：缺键 300")
    TokenSourcePreferences.setAutoIndexInterval(900, storage: autoStorage)
    assertEqual(TokenSourcePreferences.autoIndexInterval(autoStorage), 900, "间隔：往返")

    // 写入侧归一：低于下限夹到 60，非法值落默认 300
    TokenSourcePreferences.setAutoIndexInterval(30, storage: autoStorage)
    assertEqual(autoStorage.double(forKey: TokenSourcePreferences.autoIndexIntervalKey), 60,
                "间隔写入：低于 60 夹到 60")
    TokenSourcePreferences.setAutoIndexInterval(0, storage: autoStorage)
    assertEqual(autoStorage.double(forKey: TokenSourcePreferences.autoIndexIntervalKey), 300,
                "间隔写入：0 落默认 300")
    // 读侧同样归一（历史配置 / 手改 plist 里存了 5 秒）
    autoStorage.set(5.0, forKey: TokenSourcePreferences.autoIndexIntervalKey)
    assertEqual(TokenSourcePreferences.autoIndexInterval(autoStorage), 60, "间隔读取：5 秒归一为 60")

    // 归一边界：下限保留，非有限值与负数落默认
    assertEqual(TokenSourcePreferences.normalizedInterval(60), 60, "归一：下限保留")
    assertEqual(TokenSourcePreferences.normalizedInterval(59.9), 60, "归一：略低于下限夹到 60")
    assertEqual(TokenSourcePreferences.normalizedInterval(300), 300, "归一：正常值不变")
    assertEqual(TokenSourcePreferences.normalizedInterval(-5), 300, "归一：负数落默认")
    assertEqual(TokenSourcePreferences.normalizedInterval(.infinity), 300, "归一：非有限值落默认")

    print("✅ 多来源偏好键 works")
}
