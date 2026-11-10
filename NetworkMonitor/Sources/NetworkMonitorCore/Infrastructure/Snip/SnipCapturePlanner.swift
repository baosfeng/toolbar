import Foundation

// MARK: - 截图捕获路径规划

/// 可用截图路径 — 按优先级排列，前一条失败就降级到后一条
///
/// 实测 macOS 26/27 上 `SCScreenshotConfiguration` 会间歇返回 -3811「无法开始流播放」，
/// 而同一时刻 `captureImage(in:)` 与 `SCContentFilter` 路径正常。
/// 因此捕获入口按「新接口优先、旧接口兜底」排成一条链，任一成功即返回。
public enum SnipCapturePath: Equatable, Sendable {
    /// macOS 26+：SCScreenshotConfiguration（SDR / 光标可控）
    case screenshotConfiguration
    /// macOS 15.2+：按矩形直接抓
    case rect
    /// macOS 14+：SCContentFilter + 手动像素尺寸（最稳，永远是链尾兜底）
    case filter

    /// 可读名（日志里指出是哪条路径失败）
    public var displayName: String {
        switch self {
        case .screenshotConfiguration: return "SCScreenshotConfiguration"
        case .rect: return "captureImage(rect)"
        case .filter: return "SCContentFilter"
        }
    }
}

/// 路径规划 — 纯函数，调用方与测试共用同一判据
public enum SnipCapturePlanner {

    /// 当前系统版本可用的路径顺序
    /// - Parameters:
    ///   - isMacOS26OrNewer: 是否 macOS 26 及以上
    ///   - isMacOS15_2OrNewer: 是否 macOS 15.2 及以上
    public static func availablePaths(isMacOS26OrNewer: Bool,
                                      isMacOS15_2OrNewer: Bool) -> [SnipCapturePath] {
        var paths: [SnipCapturePath] = []
        if isMacOS26OrNewer { paths.append(.screenshotConfiguration) }
        if isMacOS15_2OrNewer { paths.append(.rect) }
        // 兜底路径无条件存在：它是 macOS 14 的能力下限，也是新接口失败时的最后一道
        paths.append(.filter)
        return paths
    }
}
