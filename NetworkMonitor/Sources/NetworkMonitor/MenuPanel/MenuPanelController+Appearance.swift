import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign

// MARK: - 菜单面板控制器（外观与渲染档）

/// 外观绑定 —— 主题 / 玻璃开关 / 渲染帧率档的热生效链路
///
/// 链路：设置页写 `AppearancePreferences` → `AppEvents.postAppearanceChanged()` /
/// `postRenderTierChanged()` → 本扩展重新应用并广播重绘。
///
/// 为什么必须有这一层：主题换的是「语义角色 → 色值」的映射，所有视图都得重新解析
/// 动态色才会更新；只写存储不发事件，表现就是「设置页切了，面板一点反应都没有」。
extension MenuPanelController {

    /// 订阅外观与渲染档变更（主类 init 末尾调用，只注册一次）
    func bindAppearance() {
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: AppEvents.appearanceChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.applyAppearance() }
        }
        renderTierObserver = NotificationCenter.default.addObserver(
            forName: AppEvents.renderTierChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let preferences = AppearancePreferences(storage: self.storage)
                self.applyAppearance()
                self.applyRenderTier(preferences.renderTier)
            }
        }
        applyAppearance()
    }

    /// 应用主题与玻璃开关：更新令牌层状态 → 重建面板材质 → 递归重绘
    func applyAppearance() {
        let preferences = AppearancePreferences(storage: storage)
        ThemeStyle.apply(theme: preferences.theme,
                         glassEnabled: preferences.glassEnabled,
                         profile: preferences.renderProfile)
        content.refreshBackdrop()
        content.markSubtreeNeedsDisplay()
        logger.info("外观已应用：主题=\(preferences.theme.displayName) "
                    + "玻璃=\(preferences.glassEnabled ? "开" : "关")")
    }

    /// 应用渲染帧率档：改写采样点上限与动效时长（中频间隔直接读档位，不另存）
    ///
    /// `maxHistory` 与 `MotionKit.durations` 是**实例/可变**状态（改造前是 `static let`，
    /// 换档不生效）；中频间隔不另存，直接读当前档位（见 `midInterval`）。
    /// Timer 周期不在这里改——它归 `MenuBarManager`（同一个 Timer 同时驱动状态栏与面板）。
    func applyRenderTier(_ tier: RenderTier) {
        currentRenderTier = tier
        let profile = RenderTierLogic.profile(for: tier)
        maxHistory = profile.historyPoints
        // 点数变少时立刻裁剪，否则旧历史会把折线按旧上限继续画
        if downHistory.count > maxHistory {
            downHistory.removeFirst(downHistory.count - maxHistory)
        }
        if upHistory.count > maxHistory {
            upHistory.removeFirst(upHistory.count - maxHistory)
        }
        MotionKit.apply(profile: profile)
        // 玻璃的默认开关随档位走（省电档关玻璃）：这里一并刷新令牌层状态，
        // 与 `applyAppearance()` 的合成规则共用同一个纯函数，两处不会分叉
        let preferences = AppearancePreferences(storage: storage)
        ThemeStyle.apply(theme: preferences.theme,
                         glassEnabled: RenderTierLogic.effectiveGlass(override: preferences.glassOverride,
                                                                     tier: tier),
                         profile: profile)
        content.refreshBackdrop()
        logger.info("渲染档已应用：\(RenderTierLogic.summary(for: tier))")
    }
}