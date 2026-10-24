import CoreGraphics

// MARK: - 窗口信息

/// 屏幕上的一层普通窗口 — 全局 CG 坐标（左上原点，单位点）
public struct SnipWindowInfo: Equatable, Sendable {
    public let windowID: UInt32
    public let frame: CGRect
    public let ownerPID: Int32
    public let ownerName: String
    public let title: String

    public init(windowID: UInt32, frame: CGRect, ownerPID: Int32, ownerName: String, title: String) {
        self.windowID = windowID
        self.frame = frame
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.title = title
    }

    /// 面积，用于在嵌套窗口里取最小者
    public var area: CGFloat { frame.width * frame.height }
}

// MARK: - 窗口命中

/// 窗口命中判定 — 纯函数，便于单测
public enum SnipWindowHitTesting {

    /// 命中包含该点的最靠前窗口 — CGWindowList 已按前后序返回，取第一个命中者
    ///
    /// 不能按面积取最小：面积小的窗口可能在后面（例如被大窗口遮住的设置面板），
    /// 那样高亮的就不是用户眼睛看到的那个窗口。
    public static func window(at point: CGPoint, in windows: [SnipWindowInfo]) -> SnipWindowInfo? {
        windows.first { $0.frame.contains(point) }
    }

    /// 过滤掉过小的窗口与自身进程窗口
    public static func usable(windows: [SnipWindowInfo],
                              excludingPID: Int32,
                              minimumSide: CGFloat = 20) -> [SnipWindowInfo] {
        windows.filter { window in
            window.ownerPID != excludingPID
                && window.frame.width >= minimumSide
                && window.frame.height >= minimumSide
        }
    }
}
