import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 贴图窗的缩放与透明度（滚轮 / 键位 / 中键共用出口）

/// 从 PinWindow.swift 拆出：主文件只保留窗口自身的核心职责
/// （建窗 / 键盘 / 变换 / 棋盘底 / 右键菜单）。
///
/// 收口理由（用户报的 bug）：「我移动贴图的时候，贴图的透明度还会发生变化，越来越透明了」。
/// 与透明度有关的三条路径原先散在主文件里（滚轮、键位 ⌃+ / ⌃-、中键重置），
/// 每条各写一份钳制区间，于是拖动时被带出的滚轮事件没人拦得住。
/// 现在三条路径共用 setAlpha，判据（含拖动 / 惯性两道闸）全在
/// NetworkMonitorUI 的 PinScrollAdjustment。
extension PinWindow {

    // MARK: - 滚轮：缩放 / 透明度

    /// 拖动会话开始 / 结束（PinContentView 调用；跨文件访问故放宽为 internal）
    func setDraggingWindow(_ dragging: Bool) {
        isDraggingWindow = dragging
    }

    /// 滚轮：裸滚轮缩放、⌃ + 滚轮调透明度
    ///
    /// 判据全在 PinScrollAdjustment（惯性放行 / 拖动中忽略 / 按设备取步长），
    /// 这里只把 NSEvent 的阶段映射一次再落副作用 —— 改前直接读 scrollingDeltaY × 0.03，
    /// 触控板轻轻一划（deltaY≈30）透明度就归零，是「越来越透明」的根因。
    override func scrollWheel(with event: NSEvent) {
        let intent = PinScrollAdjustment.intent(
            scrollingDeltaY: event.scrollingDeltaY,
            phase: PinScrollAdjustment.Phase(rawPhaseBits: event.phase.rawValue),
            momentumPhase: PinScrollAdjustment.Phase(rawPhaseBits: event.momentumPhase.rawValue),
            hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas,
            isControlPressed: event.modifierFlags.contains(.control),
            isDragging: isDraggingWindow)
        switch intent {
        case .ignore:
            // 惯性 / 拖动中 / 零位移：不改任何数值。
            // 不转给 super：贴图窗内没有可滚动容器，转出去只会让惯性帧继续往下传
            return
        case .alpha(let delta):
            setAlpha(PinScrollAdjustment.alpha(from: alphaValue, delta: delta))
        case .scale(let factor):
            // 以鼠标为锚缩放（Snipaste 口径）：光标底下那个内容点缩放后保持不动
            setScale(PinScrollAdjustment.scale(from: currentScale, factor: factor),
                     anchor: NSEvent.mouseLocation)
        }
    }

    // MARK: - 缩放

    /// 缩放贴图
    ///
    /// - Parameter anchor: 屏幕坐标锚点；传 nil 表示以窗口中心为锚，
    ///   键盘 + / - 与缩略图开关走这条，行为与「以中心缩放」的旧实现逐点一致。
    ///   滚轮传鼠标位置，锚点下的内容点缩放前后落在同一处。
    func setScale(_ scale: CGFloat, anchor: CGPoint? = nil) {
        let clamped = PinScrollAdjustment.clampScale(scale)
        guard abs(clamped - currentScale) > 0.0001 else { return }
        currentScale = clamped
        applySize(CGSize(width: baseSize.width * clamped, height: baseSize.height * clamped),
                  anchor: anchor)
    }

    // MARK: - 透明度

    /// 设置透明度（钳制区间在 PinScrollAdjustment，全仓只定义一处）
    func setAlpha(_ alpha: CGFloat) {
        alphaValue = PinScrollAdjustment.clampAlpha(alpha)
    }

    /// 按增量调透明度（键位 ⌃+ / ⌃- 与 DEBUG 探针走这条）
    func adjustAlpha(by delta: CGFloat) {
        setAlpha(alphaValue + delta)
    }
}
