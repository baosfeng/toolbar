import AppKit
import CoreGraphics
import NetworkMonitorCore
import QuartzCore

// MARK: - 回投队列与显示帧循环

/// 拆帧、排队、按帧回投 —— 从 `ScrollSmoothingEngine` 拆出（守住单文件门禁）
///
/// 这里只做「已经决定要接管之后」的事：把一次增量摊到若干帧、每帧回投一条带魔数标记的
/// 像素级事件。队列有界、余量累积，任何异常值都在入口被限幅。
extension ScrollSmoothingEngine {

    // MARK: - 回投队列

    /// 把一次滚轮增量拆成逐帧位移入队，并确保帧循环在跑
    /// internal：拆到扩展文件后跨文件调用（同 target 内）
    func enqueue(vertical: Double, horizontal: Double, flags: CGEventFlags) {
        let resolved = parameters
        let verticalTotal = resolved.scaledDelta(vertical)
        let horizontalTotal = resolved.scaledDelta(horizontal)
        // 主轴决定帧数与曲线权重，副轴共用同一组权重（斜向滚动两轴速度一致）
        let dominant = abs(verticalTotal) >= abs(horizontalTotal) ? verticalTotal : horizontalTotal
        let weights = SmoothScrollMotion.weights(delta: dominant,
                                                 parameters: resolved,
                                                 framesPerSecond: currentRefreshRate())
        guard !weights.isEmpty else {
            // 参数在热切换窗口期被关掉：已经吞下的这条按原值一次回投，不让它凭空消失
            postScroll(vertical: verticalTotal, horizontal: horizontalTotal, flags: flags)
            return
        }
        for weight in weights {
            pendingFrames.append(ScrollFrame(vertical: verticalTotal * weight,
                                             horizontal: horizontalTotal * weight,
                                             flags: flags))
        }
        trimBacklog()
        guard startDisplayLinkIfNeeded() else {
            // 拿不到显示帧驱动（无屏 / 离屏环境）：一次性回投，绝不让滚动「吞掉后不动」
            flushPendingFrames()
            return
        }
    }

    /// 立即把队列里的位移一次投出去（帧驱动不可用时的兜底）
    func flushPendingFrames() {
        guard !pendingFrames.isEmpty else { return }
        var vertical = 0.0
        var horizontal = 0.0
        let flags = pendingFrames[0].flags
        for frame in pendingFrames {
            vertical += frame.vertical
            horizontal += frame.horizontal
        }
        pendingFrames.removeAll()
        logger.warning("显示帧驱动不可用，滚轮位移改为一次性回投（功能降级为「不平滑」）")
        postScroll(vertical: vertical, horizontal: horizontal, flags: flags)
    }

    /// 队列有界：积压超上限时丢最旧的帧（宁可少滚一点，也不让延迟越来越长）
    func trimBacklog() {
        let overflow = pendingFrames.count - Self.maximumPendingFrames
        guard overflow > 0 else { return }
        pendingFrames.removeFirst(overflow)
        logger.warning("滚轮回投队列积压，丢弃 \(overflow) 帧最旧位移")
    }

    /// 主屏刷新率（120Hz 屏按 120；读不到按 60）
    func currentRefreshRate() -> Double {
        if let refreshRateProvider { return refreshRateProvider() }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return 60 }
        let framesPerSecond = Double(screen.maximumFramesPerSecond)
        return framesPerSecond > 0 ? framesPerSecond : 60
    }

    // MARK: - 显示帧循环

    /// 启动帧循环（已在跑即成功）
    ///
    /// - Returns: 是否拿到了可用的帧驱动（false = 调用方必须立刻兜底回投）
    @discardableResult
    func startDisplayLinkIfNeeded() -> Bool {
        guard displayLink == nil else { return true }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return false }
        let link = screen.displayLink(target: self, selector: #selector(displayLinkTick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        return true
    }

    /// 停止帧循环
    func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// 每帧回投一条
    @objc func displayLinkTick(_ link: CADisplayLink) {
        guard state == .running else {
            stopDisplayLink()
            pendingFrames.removeAll()
            return
        }
        guard !pendingFrames.isEmpty else {
            stopDisplayLink()
            return
        }
        let frame = pendingFrames.removeFirst()
        postScroll(vertical: frame.vertical, horizontal: frame.horizontal, flags: frame.flags)
        if pendingFrames.isEmpty { stopDisplayLink() }
    }

    // MARK: - 事件回投

    /// 回投一条带魔数标记的像素级滚轮事件
    ///
    /// 位移先取整、不足 1 像素的余量留到下一帧 —— 曲线前几帧的位移远小于 1 像素，
    /// 直接截断会把整段动画的头尾丢掉；累积余量则保证总量守恒。
    func postScroll(vertical: Double, horizontal: Double, flags: CGEventFlags) {
        verticalResidual = clampResidual(verticalResidual + vertical)
        horizontalResidual = clampResidual(horizontalResidual + horizontal)
        let wheel1 = Int32(verticalResidual)
        let wheel2 = Int32(horizontalResidual)
        verticalResidual -= Double(wheel1)
        horizontalResidual -= Double(wheel2)
        guard wheel1 != 0 || wheel2 != 0 else { return }
        guard let event = makeScrollEvent(vertical: wheel1, horizontal: wheel2, flags: flags) else {
            return
        }
        event.post(tap: .cghidEventTap)
    }

    /// 构造像素级滚轮事件（轴 1 竖直、轴 2 水平）
    ///
    /// 四个 delta 字段都写：`point` / `fixedPt` 给像素级消费者，
    /// `delta` 给仍按行读取的旧式消费者；`isContinuous = 1` 告诉 AppKit 这是精确滚动。
    func makeScrollEvent(vertical: Int32,
                                 horizontal: Int32,
                                 flags: CGEventFlags) -> CGEvent? {
        guard let event = CGEvent(scrollWheelEvent2Source: nil,
                                  units: .pixel,
                                  wheelCount: 2,
                                  wheel1: vertical,
                                  wheel2: horizontal,
                                  wheel3: 0) else {
            logger.error("无法构造回投用的滚轮事件，放弃本帧")
            return nil
        }
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(vertical))
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(horizontal))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(vertical))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(horizontal))
        event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Int64(vertical) << 16)
        event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Int64(horizontal) << 16)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.eventSourceUserData, value: ScrollEventClassifier.injectionMarker)
        // 修饰键必须继承：Shift + 滚轮 = 横向、⌘ + 滚轮 = 缩放这类映射不能丢
        event.flags = flags
        return event
    }

    /// 残余量限幅（异常增量下不让 Int32 转换越界）
    func clampResidual(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, -Self.maximumResidualMagnitude), Self.maximumResidualMagnitude)
    }
}
