import CoreGraphics
import Foundation

// MARK: - 调整时的数值 HUD（口径，不含绘制）

/// 调整数值时跟在光标旁的读数气泡 —— 文案与几何都在这里，视图只负责画
///
/// 为什么要它：调完线宽之后，用户此前唯一的反馈是"再画一笔看效果"。
/// 工具条上的数值只有在鼠标停在按钮上（悬停气泡档）或选了常驻标签档才看得到，
/// 而调整时鼠标通常停在画布上。Snipaste 的做法是工具条常显数值 + 光标图案随笔宽变化；
/// 我们自绘覆盖层没有"光标带粗细"这套图案，所以用一块跟随光标的读数补上。
///
/// 放在 UI target：文案格式、淡出时长、避让屏幕边缘的几何都是纯口径，可单测。
public enum SnipNumericHUD {

    /// 显示多久后淡出（秒）
    ///
    /// 1.2s：比一次连续滚轮操作的间隔（约 0.1～0.3s）长得多，所以连续调整时不会闪；
    /// 又比"下一次操作"短，不会长期占屏。
    public static let visibleDuration: TimeInterval = 1.2

    /// 淡出动画时长（秒）
    public static let fadeDuration: TimeInterval = 0.25

    /// 气泡内边距
    public static let padding = CGSize(width: 10, height: 6)
    /// 气泡圆角
    public static let cornerRadius: CGFloat = 7
    /// 距离光标的偏移（右下）
    public static let cursorOffset = CGVector(dx: 14, dy: 16)

    /// 一次展示的内容
    public struct Entry: Equatable, Sendable {
        public let param: SnipNumericParam
        public let value: CGFloat
        /// 调整意图的角标（精调 / 快调），coarse 时无角标
        public let intent: SnipNumericIntent

        public init(param: SnipNumericParam, value: CGFloat, intent: SnipNumericIntent) {
            self.param = param
            self.value = value
            self.intent = intent
        }
    }

    /// 文案：`线宽 12 pt` / `透明度 60%` / `线宽 12 pt · 精调`
    ///
    /// 参数名用短名（`马赛克` 而不是 `马赛克粒度`）：气泡要贴光标、越窄越好。
    public static func text(for entry: Entry) -> String {
        let body = entry.param.shortDisplayName + " " + entry.param.format(entry.value)
        guard let badge = entry.intent.badge else { return body }
        return body + " · " + badge
    }

    /// 气泡左上角的位置
    ///
    /// 默认在光标右下；右侧 / 下方放不下时翻到另一侧，最后夹进可视区。
    /// 与放大镜的避让口径一致（放大镜在光标右下 18pt，HUD 在 14/16）。
    public static func origin(size: CGSize,
                              cursor: CGPoint,
                              bounds: CGRect,
                              margin: CGFloat = 6) -> CGPoint {
        var x = cursor.x + cursorOffset.dx
        var y = cursor.y + cursorOffset.dy
        if x + size.width > bounds.maxX - margin {
            x = cursor.x - cursorOffset.dx - size.width
        }
        if y + size.height > bounds.maxY - margin {
            y = cursor.y - cursorOffset.dy - size.height
        }
        x = min(max(x, bounds.minX + margin), max(bounds.maxX - size.width - margin, bounds.minX + margin))
        y = min(max(y, bounds.minY + margin), max(bounds.maxY - size.height - margin, bounds.minY + margin))
        return CGPoint(x: x, y: y)
    }
}
