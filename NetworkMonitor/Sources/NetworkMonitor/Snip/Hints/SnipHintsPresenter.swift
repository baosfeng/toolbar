import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 操作提示（首次进标注态）

/// 首次进标注态时浮一条操作提示，3 秒后淡出
///
/// 为什么需要：本轮把滚轮从「一格一档」改成「连续 + 三档意图」之后，
/// ⌘ 快调 / ⌥ 精调 / ⌃ 调透明度 / ⇧ 缩放图形 四条都没有任何可见入口。
/// Snipaste 的做法是放大镜里常驻操作提示，我们放大镜已经很挤，
/// 改成「首次进标注态提示一次、看过就不再打扰」（偏好键 `snip.annotation.hintsShown`）。
///
/// 为什么是独立类型而不是 SnipOverlayView 扩展：同族合计门禁只允许变小，
/// 覆盖层族已经有八个文件；提示自成一套（视图 + 计时 + 偏好回写），单独成族更干净。
@MainActor
final class SnipHintsPresenter {

    /// 提示停留时长（秒）
    static let visibleDuration: TimeInterval = 3.0
    /// 提示淡出时长（秒）
    static let fadeDuration: TimeInterval = 0.35

    /// 挂提示的父视图（由覆盖层提供，presenter 不持有窗口）
    private let hostView: () -> NSView?
    /// 选区矩形（提示贴它上方；nil = 还没选）
    private let selectionRect: () -> CGRect?
    /// 覆盖层范围（避让用）
    private let bounds: () -> CGRect
    /// 看过提示后回调（编排层据此把偏好写成 true）
    private let onShown: () -> Void

    /// 是否已经看过（进标注态时由调用方灌入偏好值）
    var alreadyShown = true
    /// 当前显示的提示视图；nil = 未显示或已淡出
    private var view: SnipAnnotationHintsView?

    init(hostView: @escaping () -> NSView?,
         selectionRect: @escaping () -> CGRect?,
         bounds: @escaping () -> CGRect,
         onShown: @escaping () -> Void) {
        self.hostView = hostView
        self.selectionRect = selectionRect
        self.bounds = bounds
        self.onShown = onShown
    }

    /// 进标注态时调一次：首次展示提示，之后静默
    ///
    /// 判据走偏好键而不是内存标记：用户「上次用过了」这件事必须跨会话成立，
    /// 否则每次重启都要再被打扰一遍。
    func showIfNeeded() {
        guard !alreadyShown, view == nil, let host = hostView() else { return }
        alreadyShown = true
        onShown()
        let hints = SnipAnnotationHintsView()
        let size = SnipAnnotationHintsView.size()
        let area = bounds()
        // 贴在选区上方 12pt；放不下就压进选区内侧顶部（与尺寸标签同一套避让口径）
        let selectionTop = selectionRect()?.minY ?? area.midY
        var originY = selectionTop - size.height - 12
        if originY < 8 {
            originY = max(selectionTop + 8, 8)
        }
        let originX = min(max((selectionRect()?.midX ?? area.midX) - size.width / 2, 8),
                          max(area.width - size.width - 8, 8))
        hints.frame = CGRect(origin: CGPoint(x: originX, y: originY), size: size)
        host.addSubview(hints)
        view = hints
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleDuration) { [weak self] in
            self?.fadeOut()
        }
    }

    /// 淡出并移除提示
    private func fadeOut() {
        guard let hints = view else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            hints.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            hints.removeFromSuperview()
            if self?.view === hints {
                self?.view = nil
            }
        }
    }
}
