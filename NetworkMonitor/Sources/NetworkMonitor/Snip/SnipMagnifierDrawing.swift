import AppKit
import NetworkMonitorCore

// MARK: - 覆盖层的小标签与放大镜绘制
//
// 从 SnipOverlayView 的绘制扩展里拆出的两个自成一体的绘制单元（同 SnipBarDrawing 之于工具条）：
// 小标签原语（黑底白字，悬停窗口名与放大镜信息条共用）与像素放大镜（网格 + 中心像素框 + 双行信息条）。
// 拆出后 SnipOverlayView 绘制扩展只留选区、边框、锚点与尺寸标签。

/// 覆盖层的小标签：黑底白字 + 圆角底
///
/// `@MainActor` 与调用方（覆盖层视图）一致：属性里装着 AppKit 的字体与颜色，
/// 不是可跨线程共享的值。
@MainActor
enum SnipLabelDrawing {

    /// 字号 / 颜色 / 内边距 —— 绘制与测量同源
    ///
    /// 放大镜的双行信息条要先量出总高才能决定贴上还是贴下，
    /// 量高若另写一套字号就会与真实绘制漂移。
    static let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11, weight: .medium),
        .foregroundColor: NSColor.white
    ]
    static let padding = NSSize(width: 5, height: 2)

    /// 按内容算出的整块尺寸（含内边距）
    static func frameSize(for text: String) -> CGSize {
        let size = (text as NSString).size(withAttributes: attributes)
        return CGSize(width: size.width + padding.width * 2,
                      height: size.height + padding.height * 2)
    }

    /// 画一个标签，返回它实际占用的矩形（双行信息条按上一行的底边排下一行）
    @discardableResult
    static func draw(_ text: String, at point: CGPoint) -> CGRect {
        let background = CGRect(origin: point, size: frameSize(for: text))
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: background, xRadius: 3, yRadius: 3).fill()
        (text as NSString).draw(at: CGPoint(x: point.x + padding.width, y: point.y + padding.height),
                                withAttributes: attributes)
        return background
    }

    /// 多行标签上下排开，贴在 `anchor` 下方；下方放不下时整组翻到上方
    ///
    /// 每行内容宽度不同，各算各的尺寸、按上一行底边排下一行，短行才不会拖出一块空底。
    static func drawStacked(_ lines: [String], under anchor: CGRect, in bounds: CGRect) {
        guard !lines.isEmpty else { return }
        let gap: CGFloat = 2
        let heights = lines.map { frameSize(for: $0).height }
        let total = heights.reduce(0, +) + gap * CGFloat(lines.count - 1)
        var y = anchor.maxY + 4
        if y + total > bounds.height { y = anchor.minY - 4 - total }
        y = max(y, 0)
        for (index, line) in lines.enumerated() {
            draw(line, at: CGPoint(x: anchor.minX, y: y))
            y += heights[index] + gap
        }
    }
}

/// 鼠标旁的像素放大镜：网格 + 中心像素框 + 坐标与色值两行信息条
@MainActor
enum SnipMagnifierDrawing {

    /// 放大镜边长与采样跨度（点）
    static let side: CGFloat = 120
    static let span: CGFloat = 15

    /// 一次绘制需要的全部输入（从覆盖层取，绘制本身不碰视图状态）
    struct State {
        let screenshot: CGImage
        let sampler: SnipPixelSampler?
        /// 鼠标位置（本地点坐标）
        let pointer: CGPoint
        /// 覆盖层范围（点）
        let bounds: CGRect
        /// 本屏在全局 CG 坐标里的原点（坐标行要显示全局坐标）
        let displayOrigin: CGPoint
        /// 取色展示格式（Shift 切换）
        let colorFormat: SnipPixelColor.DisplayFormat
    }

    /// 在鼠标旁绘制像素放大镜
    static func draw(in context: CGContext, state: State) {
        guard let sampler = state.sampler else { return }
        let pointer = state.pointer
        let bounds = state.bounds
        let margin: CGFloat = 18
        var origin = CGPoint(x: pointer.x + margin, y: pointer.y + margin)
        if origin.x + side > bounds.width { origin.x = pointer.x - margin - side }
        if origin.y + side > bounds.height { origin.y = pointer.y - margin - side }
        origin.x = min(max(origin.x, 0), max(bounds.width - side, 0))
        origin.y = min(max(origin.y, 0), max(bounds.height - side, 0))

        let scale = CGFloat(state.screenshot.width) / max(bounds.width, 1)
        let span = Self.span
        let centerX = (pointer.x * scale).rounded()
        let centerY = (pointer.y * scale).rounded()
        let srcRect = CGRect(x: centerX - (span * scale) / 2,
                             y: centerY - (span * scale) / 2,
                             width: span * scale,
                             height: span * scale)
        guard let subImage = state.screenshot.cropping(to: srcRect) else { return }

        context.saveGState()
        context.setFillColor(NSColor.black.withAlphaComponent(0.85).cgColor)
        context.fill(CGRect(x: origin.x - 2, y: origin.y - 2, width: side + 4, height: side + 4))
        context.restoreGState()

        context.saveGState()
        context.translateBy(x: 0, y: 2 * origin.y + side)
        context.scaleBy(x: 1, y: -1)
        context.draw(subImage, in: CGRect(x: origin.x, y: origin.y, width: side, height: side))
        context.restoreGState()

        let cells = Int(span)
        let cell = side / CGFloat(cells)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
        context.setLineWidth(0.5)
        for index in 0...cells {
            let offset = CGFloat(index) * cell
            context.move(to: CGPoint(x: origin.x + offset, y: origin.y))
            context.addLine(to: CGPoint(x: origin.x + offset, y: origin.y + side))
            context.move(to: CGPoint(x: origin.x, y: origin.y + offset))
            context.addLine(to: CGPoint(x: origin.x + side, y: origin.y + offset))
        }
        context.strokePath()

        let centerCell = CGPoint(x: origin.x + side / 2 - cell / 2,
                                 y: origin.y + side / 2 - cell / 2)
        context.setStrokeColor(NSColor.systemRed.cgColor)
        context.setLineWidth(1.2)
        context.stroke(CGRect(x: centerCell.x, y: centerCell.y, width: cell, height: cell))

        // 上行坐标、下行色值：先定位再取值；色值行尾的格式名是 Shift 切换的可见反馈
        let globalX = Int((pointer.x + state.displayOrigin.x).rounded())
        let globalY = Int((pointer.y + state.displayOrigin.y).rounded())
        var lines = [SnipMagnifierLabelText.coordinate(x: globalX, y: globalY)]
        if let color = sampler.color(atPixel: CGPoint(x: centerX, y: centerY)) {
            lines.append(SnipMagnifierLabelText.colorText(color, format: state.colorFormat))
        }
        SnipLabelDrawing.drawStacked(lines,
                                     under: CGRect(x: origin.x, y: origin.y, width: side, height: side),
                                     in: bounds)
    }
}
