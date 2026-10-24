import CoreGraphics

// MARK: - 捕获结果

/// 单屏捕获结果 — CGImage 为不可变数据，标注 @unchecked Sendable 以便跨 actor 传递
public struct SnipCapturedImage: @unchecked Sendable {
    public let image: CGImage
    public let display: SnipDisplay

    public init(image: CGImage, display: SnipDisplay) {
        self.image = image
        self.display = display
    }
}

// MARK: - 捕获错误

/// 截图失败原因 — 调用方据此决定引导用户授权还是展示错误
public enum SnipCaptureError: Error, Equatable, Sendable {
    /// 缺屏幕录制权限
    case permissionDenied
    /// 系统没有可用屏幕
    case noDisplays
    /// 指定 displayID 不在可共享内容里
    case displayUnavailable(UInt32)
    /// 系统版本过低，无可用捕获接口
    case systemTooOld
    /// ScreenCaptureKit 返回错误或空图
    case captureFailed(String)
}

// MARK: - 便利入口

public extension SnipCaptureServicing {
    /// 默认不捕获鼠标指针
    func captureAllDisplays() async throws -> [SnipCapturedImage] {
        try await captureAllDisplays(includeCursor: false)
    }

    func capture(display: SnipDisplay) async throws -> SnipCapturedImage {
        try await capture(display: display, includeCursor: false)
    }
}

// MARK: - 捕获服务

/// 屏幕捕获服务 — 捕获策略在实现层按系统版本分档，调用方只认点/像素口径
@MainActor
public protocol SnipCaptureServicing: AnyObject {
    /// 当前所有屏幕（全局 CG 点坐标，主屏左上为原点）
    func screens() -> [SnipDisplay]

    /// 是否已获得屏幕录制权限
    func isAuthorized() -> Bool

    /// 请求屏幕录制权限；首次调用返回 false，用户需到系统设置手动勾选后重启
    @discardableResult
    func requestAuthorization() -> Bool

    /// 捕获全部屏幕，顺序与 screens() 一致
    /// - Parameter includeCursor: 是否把鼠标指针画进图里
    func captureAllDisplays(includeCursor: Bool) async throws -> [SnipCapturedImage]

    /// 捕获单块屏幕
    func capture(display: SnipDisplay, includeCursor: Bool) async throws -> SnipCapturedImage

    /// 当前屏幕上的普通窗口（全局 CG 坐标），用于窗口检测框选
    func windowInfos() -> [SnipWindowInfo]
}
