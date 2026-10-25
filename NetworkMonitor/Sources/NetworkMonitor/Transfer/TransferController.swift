import AppKit
import NetworkMonitorCore

// MARK: - 传送页控制器

/// 传送页控制器 — 面板与 `TransferService` 的接线
///
/// 职责：订阅设备表 / 会话变化 → 刷新面板；把面板上的操作（选中设备、拖拽发送、
/// 取消任务、刷新发现）翻译成服务调用；PIN 弹窗的展示与回收。
@MainActor
final class TransferController {

    private let service: TransferService
    private let registry: DeviceRegistry
    private let preferences: TransferPreferences
    private let logger: LoggingService
    private weak var panel: TransferPaneView?
    /// 打开统一设置窗口的传输页（组合根注入：设置窗口由组合根统一持有）
    var onOpenSettings: (() -> Void)?

    private var devices: [RemoteDevice] = []
    private var sessions: [TransferSession] = []
    private var selectedDeviceId: String?
    private var statusText = "未启动"
    private var started = false

    private let pairingSheet = TransferPairingSheet()
    private let scanSheet = TransferScanSheet()
    private let notification: TransferNotification
    private var currentPendingOfferId: String?
    private var pollTimer: Timer?
    private var appearedDeviceIds: Set<String> = []

    // MARK: - 初始化

    init(service: TransferService,
         registry: DeviceRegistry,
         preferences: TransferPreferences = TransferPreferences(),
         logger: LoggingService = AppContext.shared.logger) {
        self.service = service
        self.registry = registry
        self.preferences = preferences
        self.logger = logger
        self.notification = TransferNotification(preferences: preferences, logger: logger)
    }

    /// 绑定面板并安装交互回调（`MenuPanelController` 装配时调用一次）
    func attach(panel: TransferPaneView) {
        self.panel = panel
        panel.onRefresh = { [weak self] in self?.refreshDiscovery() }
        panel.onSelectDevice = { [weak self] device in self?.select(device) }
        panel.onDropFiles = { [weak self] urls in self?.send(urls) }
        panel.onPickFiles = { [weak self] in self?.presentFilePicker() }
        panel.onOpenScanReceive = { [weak self] in self?.showScanReceive() }
        panel.onCancelSession = { [weak self] sessionId in self?.cancel(sessionId: sessionId) }
        panel.onOpenSettings = { [weak self] in self?.onOpenSettings?() }
        panel.onDismissSession = { [weak self] sessionId, deleteFiles in
            guard let self else { return }
            Task { @MainActor in
                let removed = await self.service.dismissSession(id: sessionId, deleteFiles: deleteFiles)
                self.panel?.showHint(removed
                                     ? (deleteFiles ? "已移除记录并删除文件" : "已移除记录")
                                     : "进行中的任务不能移除")
            }
        }
        render()
    }

    // MARK: - 生命周期

    /// 启动传输服务并订阅事件（幂等）
    func start() {
        guard !started else { return }
        started = true
        statusText = "启动中…"
        render()

        registry.onChange = { [weak self] updated in
            Task { @MainActor [weak self] in
                self?.devices = updated
                self?.render()
            }
        }

        Task { [weak self] in
            guard let self else { return }
            await self.service.observeSessions { [weak self] updated in
                Task { @MainActor [weak self] in
                    self?.sessions = updated
                    self?.render()
                }
            }
            await self.service.observeSessionFinished { [weak self] session in
                Task { @MainActor [weak self] in self?.handleFinished(session) }
            }
            do {
                let port = try await self.service.start()
                await MainActor.run {
                    self.statusText = "端口 \(port)"
                    self.devices = self.registry.snapshot()
                    self.refreshDiscovery()
                    self.render()
                }
            } catch let error as TransferError {
                await MainActor.run {
                    self.statusText = "启动失败"
                    self.panel?.showHint(error.message)
                    self.logger.error("传输服务启动失败：\(error.message)")
                }
            } catch {
                await MainActor.run { self.statusText = "启动失败" }
            }
        }

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollPendingOffers()
                // 每秒刷新免配对窗口倒计时
                self?.render()
            }
        }
    }

    /// 停止（`AppCoordinator.stop()` 调用）
    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        pairingSheet.close()
        scanSheet.close()
        Task { await self.service.stop() }
    }

    /// 扫码接收：签发链接 → 生成二维码 → 弹窗展示
    private func showScanReceive() {
        Task { [weak self] in
            guard let self else { return }
            let result = await self.service.issueScanLink()
            await MainActor.run {
                switch result {
                case .success(let info):
                    guard let png = QRCodeGenerator.pngData(for: info.url) else {
                        self.panel?.showHint("二维码生成失败")
                        self.logger.error("扫码接收：二维码生成失败")
                        return
                    }
                    self.scanSheet.show(info: info, qrPNG: png)
                case .failure(let error):
                    self.panel?.showHint(error.message)
                    self.logger.warning("扫码接收入口不可用：\(error.message)")
                }
            }
        }
    }

    // MARK: - 面板交互

    private func render() {
        let windowActive = preferences.isWindowActive()
        panel?.update(devices: devices,
                      sessions: sessions,
                      selectedDeviceId: selectedDeviceId,
                      statusText: statusText,
                      autoAcceptText: windowActive ? preferences.windowRemainingText() : "",
                      autoAcceptActive: windowActive)
        notifyNewDevices()
    }

    /// 新设备首次出现在列表时给轻提示（音效默认关闭，由设置开启）
    private func notifyNewDevices() {
        for device in devices where device.isOnline {
            if appearedDeviceIds.insert(device.deviceId).inserted, started {
                notification.deviceAppeared(device)
            }
        }
    }

    private func select(_ device: RemoteDevice) {
        selectedDeviceId = device.deviceId
        panel?.showHint(device.isOnline ? "已选择 \(device.alias)，拖文件或点「选择文件…」发送"
                                        : "\(device.alias) 当前离线")
        render()
    }

    private func refreshDiscovery() {
        Task { [weak self] in
            await self?.service.refreshDiscovery()
        }
    }

    private func presentFilePicker() {
        let picker = NSOpenPanel()
        picker.canChooseFiles = true
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = true
        picker.title = "选择要发送的文件"
        picker.prompt = "发送"
        guard picker.runModal() == .OK, !picker.urls.isEmpty else { return }
        send(picker.urls)
    }

    /// 发起发送（目标：选中设备 → 第一台在线设备）
    private func send(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard let target = resolveTargetDevice() else {
            panel?.showHint("没有可用的在线设备")
            return
        }
        selectedDeviceId = target.deviceId
        panel?.showHint("正在发送到 \(target.alias)…")
        Task { [weak self] in
            guard let self else { return }
            let result = await self.service.sendFiles(urls, to: target)
            await MainActor.run {
                switch result {
                case .success(let session):
                    if session.state == .awaitingConfirm {
                        self.presentPINInput(sessionId: session.id, peerName: target.alias)
                    } else if session.state == .completed {
                        self.panel?.showHint("发送完成")
                    }
                case .failure(let error):
                    self.panel?.showHint("发送失败：\(error.message)")
                }
            }
        }
    }

    private func resolveTargetDevice() -> RemoteDevice? {
        if let selectedDeviceId,
           let selected = devices.first(where: { $0.deviceId == selectedDeviceId && $0.isOnline }) {
            return selected
        }
        return devices.first { $0.isOnline }
    }

    private func cancel(sessionId: String) {
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }
        Task { [weak self] in
            guard let self else { return }
            if session.direction == .send {
                await self.service.cancelSend(sessionId: sessionId)
            } else {
                await self.service.cancelLocal(sessionId: sessionId)
            }
        }
    }

    // MARK: - PIN 配对

    /// 发送方输入 PIN（接收端展示的 4 位码）
    private func presentPINInput(sessionId: String, peerName: String) {
        pairingSheet.showInput(peerName: peerName, onSubmit: { [weak self] pin in
            guard let self else { return }
            self.pairingSheet.close()
            guard PairingStore.isValidPIN(pin) else {
                self.panel?.showHint("PIN 必须是 4 位数字")
                return
            }
            Task { [weak self] in
                guard let self else { return }
                let result = await self.service.submitPIN(pin, sessionId: sessionId)
                await MainActor.run {
                    switch result {
                    case .success(let session):
                        self.panel?.showHint(session.state == .completed ? "发送完成" : "配对成功，开始传输")
                    case .failure(let error):
                        self.panel?.showHint("配对失败：\(error.message)")
                    }
                }
            }
        }, onCancel: { [weak self] in
            self?.pairingSheet.close()
        })
    }

    /// 每秒检查一次待确认的接收请求（接收方展示 PIN）
    private func pollPendingOffers() {
        Task { [weak self] in
            guard let self else { return }
            let pending = await self.service.pendingOffers()
            await MainActor.run {
                guard let offer = pending.first else {
                    if self.currentPendingOfferId != nil {
                        self.currentPendingOfferId = nil
                        self.pairingSheet.close()
                    }
                    return
                }
                guard offer.sessionId != self.currentPendingOfferId else { return }
                self.currentPendingOfferId = offer.sessionId
                self.notification.pairingCodeGenerated()
                self.presentReceivePIN(offer)
            }
        }
    }

    /// 接收方 PIN 展示窗
    private func presentReceivePIN(_ offer: TransferService.PendingOffer) {
        // 别名优先取 offer 自身携带的 senderAlias，发现层表仅作兜底——
        // 发现层可能尚未收录该设备（或 deviceId 不匹配），此时不应显示「未知设备」
        let discovered = devices.first { $0.deviceId == offer.peerDeviceId }?.alias
        let peerName = [offer.senderAlias, discovered]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "未知设备"
        let fileNames = sessions.first { $0.id == offer.sessionId }?.files.map(\.name) ?? []
        pairingSheet.showReceive(pin: offer.pin, peerName: peerName, fileNames: fileNames,
                                 expiresAt: offer.expiresAt,
                                 onApprove: { [weak self] in
                                     guard let self else { return }
                                     self.pairingSheet.close()
                                     self.currentPendingOfferId = nil
                                     Task { await self.service.approveOffer(sessionId: offer.sessionId) }
                                 },
                                 onDeny: { [weak self] in
                                     guard let self else { return }
                                     self.pairingSheet.close()
                                     self.currentPendingOfferId = nil
                                     Task { await self.service.denyOffer(sessionId: offer.sessionId) }
                                 },
                                 onExpire: { [weak self] in
                                     self?.currentPendingOfferId = nil
                                 })
    }

    // MARK: - 会话结束

    /// 会话进入终结态：系统通知 + 系统音效
    private func handleFinished(_ session: TransferSession) {
        logger.info("传输会话结束：\(session.id) \(session.state.rawValue)")
        panel?.showHint(TransferNotification.message(for: session))
        notification.sessionFinished(session)
    }
}