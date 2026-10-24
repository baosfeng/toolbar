import AppKit
import Carbon
import NetworkMonitorCore

// MARK: - 热键注册（从编排主类拆出，守住单文件门禁）

extension SnipController {

// MARK: - 启动

    func start() {
        registerSnipHotKey()
        registerPinHotKey()
        registerDelayedSnipHotKey()
        registerHideAllPinsHotKey()
        registerSettingsHotKey()
        registerWhiteboardHotKey()
#if DEBUG
        if SnipDemo.isRequested {
            SnipDemo.run(capture: captureService, pin: pinWindows, openSettings: onOpenSettings)
        }
        runOverlayDemoIfRequested()
        runWhiteboardDemoIfRequested()
#endif
    }

    func registerSnipHotKey() {
        let primary = hotKeys.register(Self.primarySnipCombo) { [weak self] in self?.beginSnip() }
        if case .success = primary { return }
        let fallback = hotKeys.register(Self.fallbackSnipCombo) { [weak self] in self?.beginSnip() }
        if case .success = fallback {
            logger.info("截图热键回落为 \(Self.fallbackSnipCombo.displayString)")
        } else {
            logger.error("截图热键注册失败，功能不可用")
        }
    }

    func registerPinHotKey() {
        let primary = hotKeys.register(Self.primaryPinCombo) { [weak self] in self?.pinFromClipboard() }
        if case .success = primary { return }
        let fallback = hotKeys.register(Self.fallbackPinCombo) { [weak self] in self?.pinFromClipboard() }
        if case .success = fallback {
            logger.info("贴图热键回落为 \(Self.fallbackPinCombo.displayString)")
        } else {
            logger.error("贴图热键注册失败，功能不可用")
        }
    }

#if DEBUG
    /// 仅 DEBUG：NM_SNIP_OVERLAY_DEMO=1 时直接摆出覆盖层 + 选区并截图取证
    func runOverlayDemoIfRequested() {
        guard ProcessInfo.processInfo.environment["NM_SNIP_OVERLAY_DEMO"] != nil else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            do {
                let result = try await captureService.captureAllDisplays()
                captures = result
                presentOverlays(result)
                // 先取证窗口检测高亮
                overlays.first?.overlayView.debugPointerFrozen = true
                overlays.first?.overlayView.debugHover(atLocalPoint: CGPoint(x: 600, y: 330))
                try? await Task.sleep(nanoseconds: 900_000_000)
                if let hoverImage = try await captureService.captureAllDisplays().first?.image {
                    try SnipDemo.saveImage(hoverImage, to: "/tmp/nm-snip-hover.png")
                    print("demo: 已写入 /tmp/nm-snip-hover.png")
                }
                // 再取证选区态
                overlays.first?.overlayView.debugApplySelection(CGRect(x: 300, y: 300, width: 600, height: 400))
                overlays.first?.overlayView.debugAddAnnotation(
                    SnipAnnotation(kind: .rectangle,
                                   start: CGPoint(x: 340, y: 340),
                                   end: CGPoint(x: 560, y: 460),
                                   style: SnipAnnotationStyle(color: .red, lineWidth: 4)))
                overlays.first?.overlayView.debugAddAnnotation(
                    SnipAnnotation(kind: .arrow,
                                   start: CGPoint(x: 620, y: 420),
                                   end: CGPoint(x: 820, y: 560),
                                   style: SnipAnnotationStyle(color: .blue, lineWidth: 4)))
                overlays.first?.overlayView.debugAddAnnotation(
                    SnipAnnotation(kind: .polyline,
                                   start: CGPoint(x: 620, y: 320),
                                   end: CGPoint(x: 860, y: 400),
                                   points: [CGPoint(x: 620, y: 320),
                                            CGPoint(x: 720, y: 380),
                                            CGPoint(x: 800, y: 330),
                                            CGPoint(x: 860, y: 400)],
                                   style: SnipAnnotationStyle(color: .green, lineWidth: 4)))
                var rotatedText = SnipAnnotation(kind: .text,
                                                 start: CGPoint(x: 400, y: 640),
                                                 end: CGPoint(x: 400, y: 640),
                                                 text: "缩放 1.3× 且旋转 20° 的文字",
                                                 style: SnipAnnotationStyle(color: .red, lineWidth: 4))
                rotatedText.fontScale = 1.3
                rotatedText.rotation = .pi / 9
                overlays.first?.overlayView.debugAddAnnotation(rotatedText)
                overlays.first?.overlayView.debugAddAnnotation(
                    SnipAnnotation(kind: .mosaic,
                                   start: CGPoint(x: 380, y: 560),
                                   end: CGPoint(x: 800, y: 640),
                                   style: SnipAnnotationStyle()))
                overlays.first?.overlayView.debugAddAnnotation(
                    SnipAnnotation(kind: .freehand,
                                   start: CGPoint(x: 360, y: 600),
                                   end: CGPoint(x: 760, y: 660),
                                   points: (0...20).map { index in
                                       CGPoint(x: 360 + Double(index) * 20,
                                               y: 600 + sin(Double(index) / 3.0) * 18)
                                   },
                                   style: SnipAnnotationStyle(color: .yellow, lineWidth: 5)))
                try? await Task.sleep(nanoseconds: 900_000_000)
                let verify = try await captureService.captureAllDisplays()
                guard let image = verify.first?.image else { exit(3) }
                try SnipDemo.saveImage(image, to: "/tmp/nm-snip-overlay.png")
                print("demo: 已写入 /tmp/nm-snip-overlay.png")
            } catch {
                print("overlay demo error: \(error)")
                exit(4)
            }
            exit(0)
        }
    }
#endif

    /// 白板热键（⌥⇧W）
    static let whiteboardCombo = HotKeyCombo(keyCode: UInt32(kVK_ANSI_W),
                                             modifiers: UInt32(optionKey | shiftKey))

    func registerWhiteboardHotKey() {
        let result = hotKeys.register(Self.whiteboardCombo) { [weak self] in
            self?.beginWhiteboard()
        }
        if case .success = result {
            logger.info("白板热键：\(Self.whiteboardCombo.displayString)")
        } else {
            logger.warning("白板热键注册失败")
        }
    }

#if DEBUG
    /// 仅 DEBUG：NM_SNIP_WHITEBOARD_DEMO=1 时进白板并截图取证
    private func runWhiteboardDemoIfRequested() {
        guard ProcessInfo.processInfo.environment["NM_SNIP_WHITEBOARD_DEMO"] != nil else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            self.beginWhiteboard()
            try? await Task.sleep(nanoseconds: 900_000_000)
            if let image = try? await self.captureService.captureAllDisplays().first?.image {
                try? SnipDemo.saveImage(image, to: "/tmp/nm-snip-whiteboard.png")
                print("demo: 已写入 /tmp/nm-snip-whiteboard.png")
            }
            exit(0)
        }
    }
#endif

    /// 白板模式：以纯白画布代替屏幕截图，直接在上面标注后复制
    func beginWhiteboard() {
        guard overlays.isEmpty else { return }
        guard captureService.isAuthorized() else {
            SnipPermissionGuide.present(logger: logger)
            return
        }
        guard let display = captureService.screens().first,
              let board = makeWhiteboardImage(pixelSize: display.pixelSize) else {
            logger.warning("白板画布创建失败")
            return
        }
        let captured = SnipCapturedImage(image: board, display: display)
        captures = [captured]
        presentOverlays([captured])
        overlays.first?.overlayView.selectFullBoard()
        logger.info("白板模式已就绪")
    }

    private func makeWhiteboardImage(pixelSize: CGSize) -> CGImage? {
        let width = Int(pixelSize.width)
        let height = Int(pixelSize.height)
        guard width > 0, height > 0 else { return nil }
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: bitmapInfo) else {
            return nil
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        return context.makeImage()
    }

    func registerSettingsHotKey() {
        let result = hotKeys.register(Self.settingsCombo) { [weak self] in
            self?.onOpenSettings?()
        }
        if case .success = result {
            logger.info("设置窗热键：\(Self.settingsCombo.displayString)")
        } else {
            logger.warning("设置窗热键注册失败")
        }
    }

    func registerHideAllPinsHotKey() {
        let result = hotKeys.register(Self.hideAllPinsCombo) { [weak self] in
            self?.pinWindows.toggleHidden()
        }
        if case .success = result {
            logger.info("隐藏全部贴图热键：\(Self.hideAllPinsCombo.displayString)")
        } else {
            logger.warning("隐藏全部贴图热键注册失败")
        }
    }

    func registerDelayedSnipHotKey() {
        let result = hotKeys.register(Self.delayedSnipCombo) { [weak self] in self?.beginDelayedSnip() }
        if case .success = result {
            logger.info("延时截图热键：\(Self.delayedSnipCombo.displayString)")
        } else {
            logger.warning("延时截图热键注册失败")
        }
    }
}
