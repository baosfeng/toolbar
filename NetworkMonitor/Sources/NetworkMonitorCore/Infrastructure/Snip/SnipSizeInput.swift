import CoreGraphics
import Foundation

// MARK: - 尺寸输入解析

/// 自定义截图尺寸的文本解析 — 支持 800x600 / 800*600 / 800,600 / 800 600
public enum SnipSizeInput {

    public static func parse(_ text: String) -> CGSize? {
        let normalized = text
            .replacingOccurrences(of: "×", with: "x")
            .replacingOccurrences(of: "*", with: "x")
            .replacingOccurrences(of: ",", with: "x")
            .replacingOccurrences(of: "，", with: "x")
            .lowercased()
        let parts = normalized
            .split(whereSeparator: { $0 == "x" || $0 == " " || $0 == "\t" })
            .compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        let width = parts[0], height = parts[1]
        guard width >= 1, height >= 1, width <= 100_000, height <= 100_000 else { return nil }
        return CGSize(width: width, height: height)
    }
}

// MARK: - 长宽比锁定

/// 按住 Shift 调整选区时保持原长宽比
public enum SnipAspectLock {

    /// 按原矩形长宽比缩放；anchor 为对角固定点
    public static func lockedResize(handle: SnipSelectionState.Handle,
                                     origin: CGRect,
                                     dx: CGFloat,
                                     dy: CGFloat,
                                     minimum: CGFloat = 1) -> CGRect {
        guard handle != .move else {
            return origin.offsetBy(dx: dx, dy: dy)
        }
        let ratio = origin.width / max(origin.height, 0.0001)

        let isHorizontal: Bool
        switch handle {
        case .left, .right, .topLeft, .bottomLeft, .topRight, .bottomRight:
            isHorizontal = true
        case .top, .bottom:
            isHorizontal = false
        case .move:
            isHorizontal = true
        }

        var width: CGFloat
        if isHorizontal {
            let growsLeft = (handle == .left || handle == .topLeft || handle == .bottomLeft)
            let candidate = max(origin.width + (growsLeft ? -dx : dx), minimum)
            width = candidate
        } else {
            let growsUp = (handle == .top)
            let candidateHeight = max(origin.height + (growsUp ? -dy : dy), minimum)
            width = candidateHeight * ratio
        }
        // 宽高都要满足最小值：按比例反推最小宽度
        let minimumWidth = max(minimum, minimum * ratio)
        width = max(width, minimumWidth)
        let height = width / ratio

        let growsLeft = (handle == .left || handle == .topLeft || handle == .bottomLeft)
        let growsUp = (handle == .top || handle == .topLeft || handle == .topRight)
        let x = growsLeft ? origin.maxX - width : origin.minX
        let y = growsUp ? origin.maxY - height : origin.minY
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
