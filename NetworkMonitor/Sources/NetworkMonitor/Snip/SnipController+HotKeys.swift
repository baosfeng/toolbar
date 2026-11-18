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
        SnipToolBarSnapshot.runIfRequested()
        SnipOverlaySnapshot.runIfRequested()
        if SnipCropProbe.isRequested {
            SnipCropProbe.run(controller: self)
        }
        SnipParityProbe.runIfRequested()
        // NM_SNIP_DOCK_PROBE=1：走完一次真实截图并断言全程没有 Dock 图标（见 SnipDockProbe）
        if SnipDockProbe.isRequested {
            SnipDockProbe.run(controller: self)
        }
#endif
    }

    private func registerSnipHotKeyAction(_ action: SnipHotKeyAction, combo: HotKeyCombo) -> Bool {
        let result = hotKeys.register(combo) { [weak self] in
            self?.performSnipHotKeyAction(action)
        }
        switch result {
        case .success(let id):
            if let oldID = registeredHotKeyIDs[action] {
                hotKeys.unregister(oldID)
            }
            registeredHotKeyIDs[action] = id
            return true
        case .conflict, .failed:
            return false
        }
    }

    private func performSnipHotKeyAction(_ action: SnipHotKeyAction) {
        switch action {
        case .screenshot: beginSnip()
        case .pin: pinFromClipboard()
        case .delayedScreenshot: beginDelayedSnip()
        case .hidePins: pinWindows.toggleHidden()
        case .settings: onOpenSettings?()
        case .whiteboard: beginWhiteboard()
        }
    }

    @discardableResult
    func updateHotKey(for action: SnipHotKeyAction, combo: HotKeyCombo) -> Bool {
        if registerSnipHotKeyAction(action, combo: combo) {
            hotKeyPreferences.setCombo(combo, for: action)
            logger.info("截图快捷键已更新：\(action.displayName) → \(combo.displayString)")
            return true
        }
        logger.warning("截图快捷键注册失败：\(combo.displayString)")
        return false
    }

    func registerSnipHotKey(combo: HotKeyCombo? = nil) {
        let requested = combo ?? hotKeyPreferences.combo(for: .screenshot)
        guard registerSnipHotKeyAction(.screenshot, combo: requested) else {
            guard requested != SnipHotKeyAction.screenshot.defaultCombo,
                  registerSnipHotKeyAction(.screenshot, combo: SnipHotKeyAction.screenshot.defaultCombo) else {
                logger.error("截图热键注册失败，功能不可用")
                return
            }
            logger.info("截图热键回落为 \(SnipHotKeyAction.screenshot.defaultCombo.displayString)")
            return
        }
        hotKeyPreferences.setCombo(requested, for: .screenshot)
        logger.info("截图热键：\(requested.displayString)")
    }

    func registerPinHotKey(combo: HotKeyCombo? = nil) {
        let requested = combo ?? hotKeyPreferences.combo(for: .pin)
        guard registerSnipHotKeyAction(.pin, combo: requested) else {
            logger.error("贴图热键注册失败，功能不可用")
            return
        }
        hotKeyPreferences.setCombo(requested, for: .pin)
        logger.info("贴图热键：\(requested.displayString)")
    }

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

    /// 白板模式：以纯白画布代替屏幕截图，直接在上面标注后复制
    func beginWhiteboard() {
        guard overlays.isEmpty else { return }
        guard captureService.isAuthorized() else {
            SnipPermissionGuide.presentIfNeeded(logger: logger)
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
