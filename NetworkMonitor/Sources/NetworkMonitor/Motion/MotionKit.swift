import AppKit

// MARK: - 全 App 统一动效入口

/// 全 App 共用动效基础设施 — 单一时长 / 曲线来源，跟随系统「减弱动态效果」
///
/// 口径（设计规格 §3.1 B1）：状态 0.12s、展开 0.34s、弹层 0.22s、关闭 0.15s、错峰 0.024s，
/// 曲线统一 `easeOut`。互传的 `TransferMotion` 是存量实现、本批不动，两者取值保持同口径。
/// 系统开启「减弱动态效果」时所有方法直接落终态，不做任何逐帧过渡。
///
/// 使用约定：剪贴板 / 菜单面板 / 设置一律调本入口，不再各模块自写 CAAnimation。
@MainActor
enum MotionKit {

    // MARK: 取值

    /// 时长与错峰令牌（与 `TransferMotion` 同口径）
    struct Durations: Sendable {
        /// 状态变化（选中切换 / 按下松开 / 图层交叉过渡）
        let state: TimeInterval
        /// 展开 / 淡入
        let expand: TimeInterval
        /// 弹层出现
        let overlay: TimeInterval
        /// 关闭 / 删除
        let close: TimeInterval
        /// 列表逐项延迟（错峰步长）
        let stagger: TimeInterval

        /// 设计规格冻结的默认取值
        static let standard = Durations(state: 0.12, expand: 0.34,
                                        overlay: 0.22, close: 0.15, stagger: 0.024)
    }

    /// 全局时长令牌
    static let durations = Durations.standard

    /// 错峰累计上限（每张 0.024s，总时长封顶 0.3s）
    private static let staggerLimit: TimeInterval = 0.3

    /// 图层交叉过渡的动画键（同一图层重复过渡时先摘旧动画）
    private static let crossFadeKey = "motion.crossFade"

    /// 是否允许动效（跟随系统「减弱动态效果」开关）
    static var isEnabled: Bool {
        !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // MARK: 通用

    /// 淡入 + 上移（卡片进场 / 弹层出现）
    ///
    /// 延迟期间先落到透明起始态，避免错峰排队时元素先露一脸再淡入。
    /// - Parameters:
    ///   - view: 目标视图
    ///   - offsetY: 起始纵向偏移（pt），动画期间回落到 0
    ///   - delay: 延迟（错峰用，取值见 `stagger(index:)`）
    static func fadeIn(_ view: NSView, offsetY: CGFloat = 10, delay: TimeInterval = 0) {
        guard isEnabled else {
            view.alphaValue = 1
            view.layer?.transform = CATransform3DIdentity
            return
        }
        view.wantsLayer = true
        view.alphaValue = 0
        view.layer?.transform = CATransform3DMakeTranslation(0, offsetY, 0)
        let play = {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = self.durations.expand
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                view.animator().alphaValue = 1
            }, completionHandler: {
                MainActor.assumeIsolated { view.layer?.transform = CATransform3DIdentity }
            })
        }
        if delay <= 0 {
            MainActor.assumeIsolated { play() }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated { play() }
            }
        }
    }

    /// 淡出（卡片消失 / 弹层关闭）；动效关闭时直接落终态并回调
    static func fadeOut(_ view: NSView, duration: TimeInterval = durations.close,
                        completion: (() -> Void)? = nil) {
        guard isEnabled else {
            view.alphaValue = 0
            completion?()
            return
        }
        nonisolated(unsafe) let handler = completion
        let work = {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                view.animator().alphaValue = 0
            }, completionHandler: {
                MainActor.assumeIsolated { handler?() }
            })
        }
        MainActor.assumeIsolated { work() }
    }

    // MARK: 窗口级

    /// 窗口展开起始态（在 `makeKeyAndOrderFront` **之前**调用）
    ///
    /// 允许动效时把窗口落到「透明 + 下移 offsetY」的起始态，首次合成就不会先以终态闪一帧；
    /// 不允许动效时（含 `offsetY` 为 0）直接落终态：alpha 1 + `toFrame`，后续 `fadeIn` 不再过渡。
    static func stageWindowEntrance(_ window: NSWindow, fromOffsetY offsetY: CGFloat, toFrame: NSRect) {
        guard isEnabled else {
            window.alphaValue = 1
            window.setFrame(toFrame, display: false)
            return
        }
        window.alphaValue = 0
        window.setFrame(toFrame.offsetBy(dx: 0, dy: -offsetY), display: false)
    }

    /// 窗口展开动画（在 `makeKeyAndOrderFront` **之后**调用）：alpha 0 → 1 + 位移回落到 `toFrame`
    ///
    /// 时序敏感：只在调用方已把窗口置为 key 之后再跑，避免与「先记前台 App、后合成 ⌘V」的时序耦合；
    /// 动效关闭或时长非正时直接落终态（alpha 1 + 终态 frame），不做任何过渡。
    static func fadeIn(window: NSWindow, toFrame: NSRect, duration: TimeInterval) {
        guard isEnabled, duration > 0 else {
            window.alphaValue = 1
            window.setFrame(toFrame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            window.animator().setFrame(toFrame, display: true)
        }
    }

    /// 窗口淡出（收起面板）；动效关闭或时长非正时直接落终态（alpha 0）并**同步**回调
    ///
    /// 让出 key 的 `orderOut` 仍归窗口自己负责，动效层只管不透明度：回调里由调用方 orderOut，
    /// 因此动效关闭时也等价于「立刻 orderOut、零过渡」。
    static func fadeOut(window: NSWindow, duration: TimeInterval = durations.close,
                        completion: (() -> Void)? = nil) {
        guard isEnabled, duration > 0 else {
            window.alphaValue = 0
            completion?()
            return
        }
        nonisolated(unsafe) let handler = completion
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { handler?() }
        })
    }

    /// 弹入：缩放 0.7 → 1.15 → 1（收藏星 / 栈角标这类小元素出现）
    static func popIn(_ view: NSView) {
        view.wantsLayer = true
        view.alphaValue = 1
        guard isEnabled, let layer = view.layer else { return }
        let animation = CAKeyframeAnimation(keyPath: "transform.scale")
        animation.values = [0.7, 1.15, 1.0]
        animation.keyTimes = [0, 0.6, 1]
        animation.duration = durations.overlay
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "motion.popIn")
    }

    /// 按下 / 缩小：默认缩放 0.96（删除动效传更小的目标实现「缩小」）
    static func press(_ view: NSView, scale: CGFloat = 0.96) {
        applyScale(view, to: scale, key: "motion.press")
    }

    /// 松开：恢复 1.0
    static func release(_ view: NSView) {
        applyScale(view, to: 1, key: "motion.release")
    }

    /// 失败：横向抖动 ±4pt 三次（动效关闭时不抖）
    static func shake(_ view: NSView) {
        guard isEnabled else { return }
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [-4, 4, -4, 4, -4, 4, 0]
        animation.duration = 0.3
        animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        layer.add(animation, forKey: "motion.shake")
    }

    /// 图层交叉过渡：把图层 opacity 平滑过渡到目标值（替代硬切 `needsDisplay`）
    ///
    /// - Parameters:
    ///   - layer: 目标图层（描边层 / 底色层 / 缩略图层）
    ///   - duration: 过渡时长，默认状态档 0.12s；传 0 表示直接落终态
    ///   - opacity: 目标不透明度；nil 表示按当前值反向切换（真·交叉切换）
    static func crossFade(layer: CALayer, duration: TimeInterval = durations.state,
                          to opacity: Float? = nil) {
        let target = opacity ?? (layer.opacity > 0.5 ? 0 : 1)
        guard isEnabled, duration > 0 else {
            layer.removeAnimation(forKey: crossFadeKey)
            layer.opacity = target
            return
        }
        let start = layer.presentation()?.opacity ?? layer.opacity
        layer.removeAnimation(forKey: crossFadeKey)
        layer.opacity = target
        guard abs(start - target) > 0.001 else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = start
        animation.toValue = target
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: crossFadeKey)
    }

    /// 视图级交叉过渡：把视图 `alphaValue` 平滑过渡到目标值（替代硬切 `needsDisplay`）
    ///
    /// 用于「叠色 / 加粗描边」这类由覆盖视图承担的选中与 hover 状态：两层同时存在，
    /// 只过渡各自的不透明度，视觉上就是一次颜色交叉溶解，不涉及重绘。
    /// - Parameters:
    ///   - view: 目标视图
    ///   - duration: 过渡时长，默认状态档 0.12s；传 0 表示直接落终态
    ///   - alpha: 目标不透明度
    static func crossFade(view: NSView, duration: TimeInterval = durations.state, to alpha: CGFloat) {
        view.wantsLayer = true
        guard isEnabled, duration > 0 else {
            view.alphaValue = alpha
            return
        }
        guard abs(view.alphaValue - alpha) > 0.001 else { return }
        // 视图版过渡 alphaValue（图层版过渡 opacity）：AppKit 会按 alphaValue 重置
        // backing layer 的 opacity，直接写 layer.opacity 会被它覆盖，因此两者各管各的属性，
        // 时长与曲线共用同一份令牌
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            view.animator().alphaValue = alpha
        }
    }

    /// 错峰延迟：第 index 个元素的进场延迟（每张 0.024s，总时长封顶 0.3s）
    static func stagger(index: Int) -> TimeInterval {
        min(Double(max(0, index)) * durations.stagger, staggerLimit)
    }

    // MARK: 内部

    /// 缩放动画落地（from = 当前呈现值，to = 目标）
    private static func applyScale(_ view: NSView, to scale: CGFloat, key: String) {
        view.wantsLayer = true
        guard isEnabled, let layer = view.layer else {
            view.layer?.transform = CATransform3DIdentity
            return
        }
        let current = layer.presentation()?.transform ?? layer.transform
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = current.m11
        animation.toValue = scale
        animation.duration = durations.state
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: key)
        layer.transform = CATransform3DMakeScale(scale, scale, 1)
    }
}