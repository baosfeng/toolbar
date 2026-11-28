import CoreGraphics

// MARK: - 覆盖层 ↔ 捕获图配对

/// 把「屏幕上的覆盖层」与「抓到的整屏图」配成一对的唯一判据
///
/// 为什么不再用 frame 相等：覆盖层的 frame 由 `CGDisplayBounds` 翻转算出来，
/// 而 `NSWindow` 会把 frame 取整到设备像素。多屏、缩放档、屏幕重排之后两者
/// 会差 0.5pt 这一级，浮点相等就再也配不上——用户看到的是「复制 / 保存点了
/// 毫无反应、截图界面退不出去」，而日志里只有一条「找不到覆盖层对应的捕获图」。
///
/// 判据按可靠度分级：
/// 1. `displayID`（CoreGraphics 的稳定标识，几何怎么变都不影响）；
/// 2. frame 全等（老口径，兼容 displayID 缺失的假实现）；
/// 3. 只有一张捕获图时直接给它（单屏无歧义，比配不上好）。
public enum SnipCaptureMatching {

    /// 取出某个覆盖层对应的捕获图
    /// - Parameters:
    ///   - displayID: 覆盖层所在屏幕的 CoreGraphics display id
    ///   - frame: 覆盖层窗口 frame（仅作第二级兜底）
    public static func capture(forDisplayID displayID: UInt32,
                               frame: CGRect,
                               in captures: [SnipCapturedImage]) -> SnipCapturedImage? {
        if let exact = captures.first(where: { $0.display.displayID == displayID }) {
            return exact
        }
        if let byFrame = captures.first(where: { $0.display.frame == frame }) {
            return byFrame
        }
        // 单屏时不存在歧义：宁可给唯一那张，也不要让整条输出链路静默失效
        return captures.count == 1 ? captures.first : nil
    }
}
