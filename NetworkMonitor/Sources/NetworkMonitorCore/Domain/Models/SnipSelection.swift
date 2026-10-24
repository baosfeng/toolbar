import CoreGraphics

// MARK: - 屏幕几何

/// 一块屏幕的几何信息 — 全局 CG 坐标（左上原点，单位点）与捕获图像素尺寸
public struct SnipDisplay: Equatable, Sendable {
    /// 屏幕在全局 CG 坐标系中的矩形（点）
    public let frame: CGRect
    /// 该屏捕获图的像素尺寸（Retina 屏为点尺寸的整数倍）
    public let pixelSize: CGSize
    /// CoreGraphics display ID
    public let displayID: UInt32

    public init(frame: CGRect, pixelSize: CGSize, displayID: UInt32) {
        self.frame = frame
        self.pixelSize = pixelSize
        self.displayID = displayID
    }

    /// 缩放比（像素 / 点）；几何异常时回落到 1
    public var backingScale: CGFloat {
        guard frame.width > 0, pixelSize.width > 0 else { return 1 }
        return pixelSize.width / frame.width
    }
}

// MARK: - 选区

/// 一次截图选区 — 已归一化的全局 CG 点坐标矩形
public struct SnipSelection: Equatable, Sendable {
    /// 选区矩形（宽高均为正）
    public let rect: CGRect

    /// 最小可成立边长（点）；低于此值视为误触
    public static let minimumSide: CGFloat = 1

    /// 归一化构造；宽或高小于阈值时返回 nil
    public init?(rect: CGRect, minimumSide: CGFloat = SnipSelection.minimumSide) {
        guard rect.width >= minimumSide, rect.height >= minimumSide else { return nil }
        self.rect = rect
    }
}
