import AppKit
import QuartzCore

// MARK: - 自绘过渡值

/// 自绘控件的过渡值 —— 一个 0…1 的混合系数，按 `MotionKit` 的时长与曲线逐帧推进
///
/// 为什么需要它：改造前「hover 提亮 / 选中叠色 / 缩略图淡入 / 角标弹入」各自是一个子视图，
/// 动效靠 `alphaValue` / `CAKeyframeAnimation` 完成。整卡自绘后没有子视图可动，
/// 这些过渡改由一个数值驱动整卡重绘——时长、曲线、是否允许动效仍**全部取自 MotionKit**，
/// 系统「减弱动态效果」或渲染档关闭动效时直接落终态（不逐帧）。
///
/// 成本：只有正在过渡的那张卡有 Timer（60fps，0.12–0.22s），静止时 timer 为 nil。
@MainActor
public final class DrawnBlend {

    /// 当前值（绘制侧直接读）
    public private(set) var value: CGFloat = 0

    public init() {}

    /// 插值帧间隔（60fps；过渡最长 0.22s，最多 13 帧）
    private static let frameInterval: TimeInterval = 1.0 / 60.0

    private var timer: Timer?
    private var from: CGFloat = 0
    private var to: CGFloat = 0
    private var duration: TimeInterval = 0
    private var startedAt: CFTimeInterval = 0
    private var onChange: ((CGFloat) -> Void)?

    /// 过渡到目标值
    /// - Parameters:
    ///   - target: 目标值
    ///   - duration: 时长（默认 `MotionKit.durations.state`；0 = 直接落终态）
    ///   - onChange: 每帧回调（一般只置 `needsDisplay = true`）
    public func animate(to target: CGFloat, duration: TimeInterval = MotionKit.durations.state,
                 onChange: ((CGFloat) -> Void)? = nil) {
        self.onChange = onChange
        let start = value
        stopTimer()
        guard MotionKit.isEnabled, duration > 0, abs(target - start) > 0.001 else {
            value = target
            onChange?(value)
            return
        }
        from = start
        to = target
        self.duration = duration
        startedAt = CACurrentMediaTime()
        let timer = Timer(timeInterval: Self.frameInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        advance()
    }

    /// 直接落值（内容复用 / 布局复位时用，不播过渡）
    public func set(_ newValue: CGFloat) {
        stopTimer()
        value = newValue
    }

    /// 停止在途过渡（保持当前值）
    func cancel() {
        stopTimer()
    }

    isolated deinit {
        timer?.invalidate()
    }

    // MARK: 内部

    private func advance() {
        let elapsed = CACurrentMediaTime() - startedAt
        let progress = duration > 0 ? min(max(elapsed / duration, 0), 1) : 1
        value = from + (to - from) * MotionKit.easedOut(CGFloat(progress))
        onChange?(value)
        guard progress >= 1 else { return }
        stopTimer()
        value = to
        onChange?(value)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
