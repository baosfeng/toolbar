import AppKit
import CoreGraphics
import NetworkMonitorCore
import ScreenCaptureKit

// MARK: - 屏幕捕获实现

/// 屏幕捕获 — 按系统版本三档实现：26+ 用 SCScreenshotConfiguration，15.2+ 用按矩形抓取，
/// 14.0+ 回落到 SCContentFilter + 手动像素尺寸。全部路径都要求屏幕录制权限。
@MainActor
final class ScreenCaptureService: SnipCaptureServicing {

    /// 日志（捕获路径降级时记录被跳过的路径与原因）
    private let logger: LoggingService

    init(logger: LoggingService = AppContext.shared.logger) {
        self.logger = logger
    }

    // MARK: - 屏幕与权限

    func screens() -> [SnipDisplay] {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let displayID = CGDirectDisplayID(truncating: number)
            let frame = SelectionGeometry.cgRect(fromAppKit: screen.frame, primaryHeight: primaryHeight)
            let pixelWidth = CGDisplayPixelsWide(displayID)
            let pixelHeight = CGDisplayPixelsHigh(displayID)
            let pixelSize = pixelWidth > 0 && pixelHeight > 0
                ? CGSize(width: CGFloat(pixelWidth), height: CGFloat(pixelHeight))
                : CGSize(width: frame.width * screen.backingScaleFactor,
                         height: frame.height * screen.backingScaleFactor)
            return SnipDisplay(frame: frame, pixelSize: pixelSize, displayID: displayID)
        }
    }

    /// 可用捕获路径 — 名字用于日志，capture 为具体实现
    struct CapturePath {
        let name: String
        let capture: (SnipDisplay) async throws -> SnipCapturedImage
    }

    func isAuthorized() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    func requestAuthorization() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    // MARK: - 窗口列表

    func windowInfos() -> [SnipWindowInfo] {
        guard isAuthorized() else { return [] }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let parsed: [SnipWindowInfo] = raw.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let windowNumber = info[kCGWindowNumber as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { return nil }
            let pid = (info[kCGWindowOwnerPID as String] as? Int).map { Int32($0) } ?? 0
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            let title = info[kCGWindowName as String] as? String ?? ""
            return SnipWindowInfo(windowID: UInt32(windowNumber),
                                  frame: frame,
                                  ownerPID: pid,
                                  ownerName: owner,
                                  title: title)
        }
        // 自身进程窗口排除；面积过小的辅助窗口（提示条、浮动条）也排除
        return SnipWindowHitTesting.usable(windows: parsed, excludingPID: Int32(ownPID))
    }

    // MARK: - 捕获入口

    func captureAllDisplays(includeCursor: Bool) async throws -> [SnipCapturedImage] {
        guard isAuthorized() else { throw SnipCaptureError.permissionDenied }
        let displays = screens()
        guard !displays.isEmpty else { throw SnipCaptureError.noDisplays }
        var results: [SnipCapturedImage] = []
        results.reserveCapacity(displays.count)
        for display in displays {
            results.append(try await capture(display: display, includeCursor: includeCursor))
        }
        return results
    }

    func capture(display: SnipDisplay, includeCursor: Bool) async throws -> SnipCapturedImage {
        guard isAuthorized() else { throw SnipCaptureError.permissionDenied }
        // 需要指针时只有 filter 路径能控制 showsCursor，直接走 14+ 实现
        guard !includeCursor else {
            return try await captureWithFilter(display, includeCursor: true)
        }
        // 三条路径互为降级：单条路径失败不代表整机不可截（实测 macOS 26/27 上
        // SCScreenshotConfiguration 会间歇返回 -3811「无法开始流播放」，而
        // captureImage(in:) 与 filter 路径同一时刻正常）。任一成功即返回，
        // 只有全部失败才把最后一个错误抛给调用方。
        var lastError: (any Error)?
        for path in capturePaths() {
            do {
                return try await path.capture(display)
            } catch {
                lastError = error
                logger.warning("截图路径 \(path.name) 失败，尝试下一条：\(error)")
            }
        }
        throw lastError ?? SnipCaptureError.captureFailed("所有截图路径均失败")
    }

    /// 可用捕获路径（按优先级排列，最后一条兜底）
    private func capturePaths() -> [CapturePath] {
        var paths: [CapturePath] = []
        if #available(macOS 26.0, *) {
            paths.append(CapturePath(name: "SCScreenshotConfiguration", capture: { [weak self] display in
                guard let self else { throw SnipCaptureError.captureFailed("捕获服务已释放") }
                return try await self.captureWithScreenshotConfiguration(display)
            }))
        }
        if #available(macOS 15.2, *) {
            paths.append(CapturePath(name: "captureImage(rect)", capture: { [weak self] display in
                guard let self else { throw SnipCaptureError.captureFailed("捕获服务已释放") }
                return try await self.captureWithRect(display)
            }))
        }
        paths.append(CapturePath(name: "SCContentFilter", capture: { [weak self] display in
            guard let self else { throw SnipCaptureError.captureFailed("捕获服务已释放") }
            return try await self.captureWithFilter(display)
        }))
        return paths
    }

    // MARK: - macOS 26+

    /// 一次调用拿 SDR 图，天然 Retina 像素、可控制光标与阴影
    @available(macOS 26.0, *)
    private func captureWithScreenshotConfiguration(_ display: SnipDisplay) async throws -> SnipCapturedImage {
        let configuration = SCScreenshotConfiguration()
        configuration.showsCursor = false
        configuration.dynamicRange = .sdr
        do {
            let output = try await SCScreenshotManager.captureScreenshot(rect: display.frame,
                                                                         configuration: configuration)
            guard let image = output.sdrImage else {
                throw SnipCaptureError.captureFailed("截图输出为空")
            }
            return SnipCapturedImage(image: image, display: display)
        } catch let error as SnipCaptureError {
            throw error
        } catch {
            throw SnipCaptureError.captureFailed(error.localizedDescription)
        }
    }

    // MARK: - macOS 15.2+

    /// 按屏幕矩形抓取，跨屏时由系统拼接
    @available(macOS 15.2, *)
    private func captureWithRect(_ display: SnipDisplay) async throws -> SnipCapturedImage {
        do {
            let image = try await SCScreenshotManager.captureImage(in: display.frame)
            return SnipCapturedImage(image: image, display: display)
        } catch {
            throw SnipCaptureError.captureFailed(error.localizedDescription)
        }
    }

    // MARK: - macOS 14.0+

    /// 旧路径：需要自己按缩放比设置像素尺寸
    private func captureWithFilter(_ display: SnipDisplay, includeCursor: Bool = false) async throws -> SnipCapturedImage {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let shareable = content.displays.first(where: { $0.displayID == display.displayID }) else {
                throw SnipCaptureError.displayUnavailable(display.displayID)
            }
            let filter = SCContentFilter(display: shareable, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = Int(display.pixelSize.width)
            configuration.height = Int(display.pixelSize.height)
            configuration.showsCursor = includeCursor
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                   configuration: configuration)
            return SnipCapturedImage(image: image, display: display)
        } catch let error as SnipCaptureError {
            throw error
        } catch {
            throw SnipCaptureError.captureFailed(error.localizedDescription)
        }
    }
}
