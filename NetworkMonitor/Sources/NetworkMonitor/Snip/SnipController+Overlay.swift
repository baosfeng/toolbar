import AppKit
import NetworkMonitorCore
import NetworkMonitorFeatureSnip

// MARK: - 覆盖层生命周期与前台协调（从编排主类拆出，守住单文件门禁）

extension SnipController {

    /// 生成并上屏覆盖层；返回是否拿到键盘焦点
    func presentOverlays(_ result: [SnipCapturedImage]) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let windowInfos = captureService.windowInfos()
        let previous = lastSelection
        let history = selectionHistory
        // 开工样式来自设置页偏好：颜色 / 线宽 / 实虚线三个键此前没有任何消费方，
        // 用户改「默认颜色、线宽」对新建截图完全不生效（本轮把这条链路接上）。
        let initialStyle = SnipAnnotationStyleResolver.style(
            colorHex: storage.string(forKey: SnipPreferenceKey.annotationColor),
            lineWidth: (storage.object(forKey: SnipPreferenceKey.annotationLineWidth) as? Double).map { CGFloat($0) },
            dashed: storage.bool(forKey: SnipPreferenceKey.annotationDashed),
            text: SnipTextStylePreference.load(storage: storage),
            effect: SnipEffectStylePreference.load(storage: storage))
        // 工具条配置来自设置页：文字提示档、组顺序、组显隐、常驻工具、动作按钮显隐
        let toolbarConfiguration = SnipToolBarConfigurationResolver.load(storage: storage)
        overlays = result.map { captured in
            SnipOverlayWindow(display: captured.display,
                              screenshot: captured.image,
                              windowInfos: windowInfos,
                              lastSelection: previous,
                              history: history,
                              primaryHeight: primaryHeight,
                              initialStyle: initialStyle,
                              toolbarConfiguration: toolbarConfiguration,
                              delegate: self)
        }
        OverlayPreferences.apply(to: overlays, storage: storage, logger: logger)
        // 样式回写：覆盖层里调过的颜色 / 线宽 / 实虚线要落进偏好，下次截图还是这支笔
        for window in overlays {
            window.overlayView.onStylePersist = { [weak self] style in
                guard let self else { return }
                // hex 现在带 alpha（不透明时仍是 6 位）：半透明笔下次截图才是半透明
                storage.set(SnipAnnotationColorHex.hex(style.color), forKey: SnipPreferenceKey.annotationColor)
                storage.set(Double(style.lineWidth), forKey: SnipPreferenceKey.annotationLineWidth)
                storage.set(style.dashed, forKey: SnipPreferenceKey.annotationDashed)
                SnipTextStylePreference.save(style.text, storage: storage)
                // 马赛克 / 模糊强度也落盘：否则「这次调到 24px」下次又回 14
                SnipEffectStylePreference.save(style.effect, storage: storage)
            }
        }
        // 先装键盘兜底再上屏：上屏瞬间按下的键（双击热键、抢手速按 Esc）也要能被接住
        installKeyboardFallback()
        // 只有第一屏抢 App 激活并成为 key window；其余屏只需挂到屏幕上，
        // 逐屏都 activate 会让焦点在窗口间来回跳（多屏时按键会丢）
        var keyAssigned = false
        for window in overlays {
            if keyAssigned {
                window.orderFront(nil)
            } else {
                keyAssigned = window.present()
            }
        }
        guard keyAssigned else {
            // 首次 makeKey 失败不代表收不到键盘（后面还有 12 次 / 约 1 秒的激活重试，实测多数 200ms 内成功）。
            // 旧实现在这里立刻弹「覆盖层未接管键盘」，日志里每次截图都留一条假失败；
            // 有系统层 CGEventTap 时键盘本来就能用，只有连 tap 都没有（缺输入监控权限）才值得打扰用户。
            if hasSystemKeyTap {
                logger.info("覆盖层未成为 key window，键盘由系统层 CGEventTap 兜底，鼠标选区不受影响")
            } else {
                logger.warning("截图覆盖层未能成为键盘焦点且无系统层按键兜底")
                SnipFailureNotice.present(message: "覆盖层未能接管键盘，请在系统设置里授予「输入监控」，或用鼠标选区", logger: logger)
            }
            return
        }
        logger.info("截图覆盖层已就绪，共 \(overlays.count) 屏")
    }

    /// 收掉全部覆盖层并恢复菜单栏激活策略
    func dismissOverlays() {
        for window in overlays {
            window.orderOut(nil)
            window.close()
        }
        overlays.removeAll()
        captures.removeAll()
        removeKeyboardFallback()
        restoreMenuBarPolicy()
    }

    /// 截图开始前把前台拿到手（详见 beginSnip 里的说明）
    ///
    /// 关键点：抢前台只做 activate + 让覆盖层成为 key window，**不切激活策略**。
    /// 早期这里切 .regular 是为了让系统把键盘归属交过来，代价是每次截图
    /// Dock 里都会闪出一个本应用图标（用户口径：「每次截图 dock 栏都会出现我们的软件」）。
    /// 覆盖层本身是 .nonactivatingPanel + canBecomeKey，不需要 App 变成可激活应用。
    func claimForegroundForCapture() async {
        SnipForegroundPolicy.claimForeground()
        // 抓屏本身要几百毫秒，这段空档里前台自然落稳；没落稳也不阻塞，
        // 覆盖层上屏后还有一轮有限重试（SnipOverlayWindow.scheduleActivationRetry）
        let deadline = Date().addingTimeInterval(0.6)
        let selfPID = ProcessInfo.processInfo.processIdentifier
        while Date() < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == selfPID { return }
            SnipForegroundPolicy.claimForeground()
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        logger.warning("截图前未能立刻取得前台，首下按键可能需按第二次")
    }

    /// 退出截图态：兜底确保 App 回到菜单栏态（正常路径下全程没有借出过 .regular）
    func restoreMenuBarPolicy() {
        SnipForegroundPolicy.restoreMenuBar()
    }
}