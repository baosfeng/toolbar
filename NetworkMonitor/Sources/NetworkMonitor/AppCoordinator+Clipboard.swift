import AppKit
import NetworkMonitorCore

// MARK: - 应用协调器（剪贴板与流量持久化装配）

/// 剪贴板链路与累计流量落盘的装配 — 从 `AppCoordinator.swift` 拆出
///
/// 拆出原因：组合根加入屏幕活动监听后已接近单文件 15 KiB 规范上限，
/// 按「主类 + 装配扩展」范式分离。跨文件访问的成员由 private 放宽为 internal 并注明原因。
extension AppCoordinator {

    // MARK: - 累计流量持久化

    /// 累计流量每隔 60 秒落盘
    ///
    /// 只在正常退出时保存会被崩溃 / 强杀绕过：重启后累计值回退成更旧的值，
    /// 当日流量基准随之失配（今日流量恒为 0）。定期落盘把丢失窗口压到 1 分钟。
    // 放宽为 internal：主文件 `start()` 跨文件调用（同模块内无其他调用方）
    func startTrafficPersistence() {
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.persistTrafficTotals() }
        }
        RunLoop.main.add(timer, forMode: .common)
        trafficPersistenceTimer = timer
    }

    /// 立即写入累计上下行字节
    // 放宽为 internal：主文件 `stop()` 跨文件调用
    func persistTrafficTotals() {
        AppContext.shared.storage.set(Int(networkMonitor?.totalRx ?? 0), forKey: "totalRx")
        AppContext.shared.storage.set(Int(networkMonitor?.totalTx ?? 0), forKey: "totalTx")
    }

    // MARK: - 剪贴板历史装配

    /// 装配剪贴板链路：偏好 → 写回 → 粘贴 → 采集 → 栈 → 面板 → 设置 → 全局热键
    // 放宽为 internal：主文件 `start()` 跨文件调用
    func setupClipboard(database: any AppDatabase) {
        let preferences = ClipboardPreferences()
        clipboardPreferences = preferences
        // 音效与触觉已在 setupNotificationAndFeedback 里按统一偏好装配，
        // 这里只做引用：偏好改完立即生效（播放器每次调用现读配置）。

        let writer = PasteboardWriter()
        let paster = ClipboardPaster(writer: writer, preferences: preferences)
        clipboardPaster = paster

        let watcher = PasteboardWatcher(preferences: preferences)
        clipboardWatcher = watcher
        // 落库与事件发布由组合根在回调里完成（Core 采集器不触碰仓储）
        watcher.onCapture = { [weak self] draft in self?.persistClipboardDraft(draft) }
        watcher.onStateChange = { [weak self] state in self?.handleCaptureState(state) }
        watcher.start()

        let stack = PasteStackController(repository: database, writer: writer)
        clipboardStack = stack
        stack.start()

        // 音效与触觉成对注入：面板控制器与面板视图共用同一份实例（由 setupFeedback 装配）
        let feedback = ClipboardFeedback(sound: soundFeedback, haptics: hapticFeedback)
        clipboardPanel = ClipboardPanelController(repository: database,
                                                  captureService: watcher,
                                                  paster: paster,
                                                  stack: stack,
                                                  feedback: feedback,
                                                  // ⌘, 与面板内「设置」入口都走统一设置窗口的剪贴板页
                                                  onRequestSettings: { [weak self] in
                                                      self?.settingsWindow?.show(section: .clipboard)
                                                  },
                                                  preferences: preferences)
        // 历史卡片右键「贴到屏幕」接到截图链路
        clipboardPanel.onRequestPin = { [weak self] item in
            self?.snipController.pinClipboardItem(item)
        }

        globalHotKey = GlobalHotKeyCenter()
        registerClipboardHotKey(preferences.panelToggleHotKey, presentingAlert: true)
    }

    /// 采集回调：落库 + 广播 + 超限清理 + 图片回收
    /// 死锁红线：仓储方法在串行队列 sync，须在主线程调用；禁止在 db.query(sql:handler:) 回调内调用。
    private func persistClipboardDraft(_ draft: ClipboardDraft) {
        guard let repository = database else { return }
        guard repository.saveClipboardItem(draft) != nil else {
            logger.warning("剪贴板条目落库失败（数据库未就绪或内容无效）")
            return
        }
        AppEvents.postClipboardChanged()
        // 超限清理后回收被删条目的落盘图片（文本条目零 IO，见 ClipboardImageGC）
        ClipboardImageGC.prune(repository: repository, maxItems: clipboardPreferences.maxItems,
                               retentionDays: clipboardPreferences.retentionDays, logger: logger)
    }

    /// 采集状态变化：权限被拒时明确告警（不静默）
    private func handleCaptureState(_ state: ClipboardCaptureState) {
        switch state {
        case .running:
            logger.info("剪贴板采集运行中")
        case .stopped:
            logger.info("剪贴板采集未运行（按需采集模式或已停止）")
        case .denied(let reason):
            logger.warning("剪贴板访问被拒绝（\(reason.rawValue)）：请到「系统设置 → 隐私与安全性」允许本应用访问剪贴板")
        }
    }

    /// 注册全局唤起热键；失败时不静默，引导用户去系统设置释放占用
    /// 放宽 internal：设置窗重新录制快捷键时由 AppCoordinator+ClipboardSettings 调用
    @discardableResult
    func registerClipboardHotKey(_ combo: HotKeyCombo, presentingAlert: Bool) -> Bool {
        let result = globalHotKey.register(combo) { [weak self] in self?.clipboardPanel.toggle() }
        switch result {
        case .success:
            return true
        case .conflict, .failed:
            logger.error("剪贴板全局热键注册失败：\(combo.displayString)（可能被其他应用占用）")
            if presentingAlert { presentHotKeyConflictAlert(combo) }
            return false
        }
    }

    /// 热键冲突提示（延迟到启动完成后弹出，避免阻塞 App 启动）
    private func presentHotKeyConflictAlert(_ combo: HotKeyCombo) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            let alert = NSAlert()
            alert.messageText = "快捷键 \(combo.displayString) 注册失败"
            alert.informativeText = "该组合键可能已被其他应用占用。请到「系统设置 → 键盘 → 键盘快捷键」释放占用后，在剪贴板设置中重新录制。"
            alert.addButton(withTitle: "打开剪贴板设置")
            alert.addButton(withTitle: "稍后")
            if alert.runModal() == .alertFirstButtonReturn {
                self.settingsWindow?.show(section: .clipboard)
            }
        }
    }
}
