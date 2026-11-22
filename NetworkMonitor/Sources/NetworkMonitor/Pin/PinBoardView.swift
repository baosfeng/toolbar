import AppKit
import NetworkMonitorUI

// MARK: - 棋盘底视图

/// 贴图窗最底层的棋盘格 —— 让半透明贴图的透明区一眼可辨
///
/// 贴图窗是透明背景的浮窗，半透明 PNG 的透明区直接透出桌面，
/// 用户分不清「这块内容本来长这样」还是「这块是透明的」。
/// 本视图只负责画格子，**该不该显示由 PinBoardBackgroundResolver 判**（开关 + 是否含 alpha）。
///
/// 格子边长与两档灰度都取 PinBoardBackgroundResolver 的常量，绘制里不写字面量。
@MainActor
final class PinBoardView: NSView {

    override var isOpaque: Bool { false }

    /// 装饰层不吃鼠标：命中测试一律返回 nil，点击 / 拖动 / 右键继续落在 PinContentView
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let cell = PinBoardBackgroundResolver.cellSize
        let grid = PinBoardBackgroundResolver.gridCount(for: bounds.size)
        guard grid.columns > 0, grid.rows > 0 else { return }
        let light = NSColor(white: PinBoardBackgroundResolver.Tone.light, alpha: 1)
        let dark = NSColor(white: PinBoardBackgroundResolver.Tone.dark, alpha: 1)
        for row in 0..<grid.rows {
            for column in 0..<grid.columns {
                let isLight = PinBoardBackgroundResolver.isLightCell(column: column, row: row)
                (isLight ? light : dark).setFill()
                let rect = NSRect(x: CGFloat(column) * cell,
                                  y: CGFloat(row) * cell,
                                  width: cell,
                                  height: cell)
                rect.fill()
            }
        }
    }
}
