#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 快照主题与渲染档开关（仅 DEBUG）

/// 主题 / 渲染帧率档的取证开关 —— 与 `NM_UNIT_STYLE` 同一套做法
///
/// 触发方式：
/// ```
/// NM_SNAPSHOT_DIR=/tmp/x NM_SNAPSHOT_THEME=graphite NM_SNAPSHOT_TIER=powerSave <bundle 内可执行>
/// ```
/// 只改 `ThemeStyle` 的运行时状态（不写偏好、不碰用户设置），文件名加 `-graphite` /
/// `-powerSave` 后缀，避免覆盖默认档截图。
extension MenuPanelSnapshot {

    /// 主题环境变量（取值 = `ThemeID.rawValue`）
    static let themeEnvKey = "NM_SNAPSHOT_THEME"
    /// 渲染档环境变量（取值 = `RenderTier.rawValue`）
    static let tierEnvKey = "NM_SNAPSHOT_TIER"

    /// 取证用主题（nil = 跟随真实偏好）
    static var snapshotTheme: ThemeID? {
        guard let raw = ProcessInfo.processInfo.environment[themeEnvKey], !raw.isEmpty else { return nil }
        return ThemeID(rawValue: raw)
    }

    /// 取证用渲染档（nil = 跟随真实偏好）
    static var snapshotTier: RenderTier? {
        guard let raw = ProcessInfo.processInfo.environment[tierEnvKey], !raw.isEmpty else { return nil }
        return RenderTier(rawValue: raw)
    }

    /// 文件名后缀（切主题 / 切档取证时加上，避免覆盖默认档）
    static var appearanceFileSuffix: String {
        var suffix = ""
        if let snapshotTheme, snapshotTheme != .apple { suffix += "-\(snapshotTheme.rawValue)" }
        if let snapshotTier, snapshotTier != .standard { suffix += "-\(snapshotTier.rawValue)" }
        return suffix
    }

    /// 按取证开关应用主题与渲染档（内存态，进程退出即丢弃）
    static func prepareAppearanceForSnapshot() {
        let preferences = AppearancePreferences()
        let theme = snapshotTheme.map { ThemeCatalog.theme(for: $0) } ?? preferences.theme
        let tier = snapshotTier ?? preferences.renderTier
        let profile = RenderTierLogic.profile(for: tier)
        let glass = RenderTierLogic.effectiveGlass(override: preferences.glassOverride, tier: tier)
        ThemeStyle.apply(theme: theme, glassEnabled: glass, profile: profile)
        MotionKit.apply(profile: profile)
        AppContext.shared.logger.info(
            "快照外观：主题=\(theme.displayName) 玻璃=\(glass ? "开" : "关") "
            + RenderTierLogic.summary(for: tier))
    }
}
#endif
