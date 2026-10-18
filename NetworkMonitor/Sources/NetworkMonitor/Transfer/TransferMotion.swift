import AppKit

// MARK: - 传输动效

/// 传输面板动效 — 对齐设计文档 §7.2 的 Mac 端取值
///
/// 时长取系统惯例：状态类 0.12s、展开类 0.34s、弹层 0.22s、关闭 0.15s，
/// 曲线统一 `easeOut`；系统开启「减弱动态效果」时所有动效直接落终态。
@MainActor
enum TransferMotion {

    /// 状态变化（进度 / 掉线）
    static let stateDuration: TimeInterval = 0.12
    /// 展开 / 淡入
    static let pageDuration: TimeInterval = 0.34
    /// 弹层出现
    static let overlayDuration: TimeInterval = 0.22
    /// 弹层关闭
    static let closeDuration: TimeInterval = 0.15
    /// 列表逐项延迟
    static let stagger: TimeInterval = 0.024

    /// 是否允许动效（跟随系统「减弱动态效果」）
    static var isEnabled: Bool {
        !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // MARK: - 通用

    /// 淡入 + 上移（设备 / 任务卡片出现）
    static func fadeIn(_ view: NSView, offsetY: CGFloat = 10, delay: TimeInterval = 0) {
        guard isEnabled else {
            view.alphaValue = 1
            return
        }
        nonisolated(unsafe) let target = view
        let work = {
            target.wantsLayer = true
            guard let layer = target.layer else {
                target.alphaValue = 1
                return
            }
            target.alphaValue = 0
            layer.setAffineTransform(CGAffineTransform(translationX: 0, y: offsetY))
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = pageDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                target.animator().alphaValue = 1
            }, completionHandler: {
                layer.setAffineTransform(.identity)
            })
        }
        if delay <= 0 {
            MainActor.assumeIsolated { work() }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated { work() }
            }
        }
    }

    /// 淡出（弹层关闭）
    static func fadeOut(_ view: NSView, duration: TimeInterval = closeDuration,
                        completion: (() -> Void)? = nil) {
        guard isEnabled else {
            completion?()
            return
        }
        nonisolated(unsafe) let target = view
        nonisolated(unsafe) let handler = completion
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            target.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { handler?() }
        })
    }

    /// 弹层出现：淡入 + 缩放 0.96 → 1
    static func popIn(_ view: NSView) {
        view.wantsLayer = true
        guard let layer = view.layer, isEnabled else {
            view.alphaValue = 1
            return
        }
        view.alphaValue = 0
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = 0.96
        animation.toValue = 1.0
        animation.duration = overlayDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "pop-in")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = overlayDuration
            view.animator().alphaValue = 1
        }
    }

    // MARK: - 状态类

    /// 失败：横向抖动 ±4px 三次
    static func shake(_ view: NSView) {
        guard isEnabled else { return }
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [-4, 4, -4, 4, -4, 4, 0]
        animation.duration = 0.3
        animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        layer.add(animation, forKey: "shake")
    }

    /// 完成：对勾弹入（缩放 0.7 → 1.1 → 1）
    static func checkmarkPop(_ view: NSView) {
        guard isEnabled else { return }
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        let animation = CAKeyframeAnimation(keyPath: "transform.scale")
        animation.values = [0.7, 1.1, 0.96, 1.0]
        animation.keyTimes = [0, 0.55, 0.8, 1]
        animation.duration = overlayDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "checkmark-pop")
    }

    /// 按下：缩放 0.96（120ms）
    static func press(_ view: NSView) {
        guard isEnabled else { return }
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = 1.0
        animation.toValue = 0.96
        animation.duration = stateDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "press")
    }

    /// 松开：恢复 1.0
    static func release(_ view: NSView) {
        guard isEnabled else { return }
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = 0.96
        animation.toValue = 1.0
        animation.duration = stateDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "release")
    }

    /// 进度插值：120ms 内把轨道从当前值补间到目标值
    static func animateProgress(_ track: MenuPanelTrackView, to fraction: Double) {
        guard isEnabled else {
            track.fraction = fraction
            return
        }
        let start = track.fraction
        guard abs(start - fraction) > 0.001 else { return }
        let steps = 8
        for step in 1...steps {
            let ratio = Double(step) / Double(steps)
            let value = start + (fraction - start) * ratio
            DispatchQueue.main.asyncAfter(deadline: .now() + stateDuration * ratio) { [weak track] in
                track?.fraction = value
            }
        }
    }
}
