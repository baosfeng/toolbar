import AppKit
import NetworkMonitorCore

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

    /// 应用渲染帧率档：改写中频节流、采样点上限与动效时长
    ///
    /// 三处都是**实例/可变**状态（改造前是 `static let`，换档不生效）：
    /// `midInterval`、`maxHistory`、`MotionKit.durations`。
    /// Timer 周期不在这里改——它归 `MenuBarManager`（同一个 Timer 同时驱动状态栏与面板）。
    func applyRenderTier(_ tier: RenderTier) {
        currentRenderTier = tier
        let profile = RenderTierLogic.profile(for: tier)
        midInterval = profile.midInterval
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

#if DEBUG

// MARK: - 结构自证（仅 DEBUG：被 MenuBarManager+Evidence 与 Debug/AppearanceEvidence 调用）

/// 面板玻璃 / 基色层的运行时结构 —— 材质类改动的**主判据**
///
/// 离屏 `cacheDisplay` 画不出窗口服务器的模糊合成（见 `docs/踩坑/运行时/毛玻璃材质离屏不可辨.md`），
/// 所以「玻璃有没有真的挂上」不能看图，只能读结构：类型、圆角、基色层 alpha、层级顺序。
extension MenuPanelController {

    /// 面板实际生效的档位（与偏好可能分叉，自证就靠这个差）
    var currentTierForEvidence: RenderTier { currentRenderTier }

    /// 当前中频刷新间隔（切档自证用）
    var midIntervalForEvidence: TimeInterval { midInterval }

    /// 当前折线采样点上限（切档自证用）
    var historyPointsForEvidence: Int { maxHistory }

    /// 返回（玻璃层类型名, 圆角, 基色层 alpha, 玻璃是否在最底层）
    func backdropStructureForEvidence() -> (glassType: String, cornerRadius: CGFloat,
                                            veilAlpha: CGFloat, glassIsBottom: Bool) {
        content.backdropStructureForEvidence()
    }
}

#endif
