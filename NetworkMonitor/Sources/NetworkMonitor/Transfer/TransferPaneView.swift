import AppKit
import NetworkMonitorCore

// MARK: - 传送页

/// 传送页 — 附近设备 + 拖拽发送 + 传输任务进度
///
/// 交互：点击设备选中为发送目标；拖文件到面板（或点「选择文件」）即向选中设备发起传输；
/// 点击任务行取消任务。数据由 `TransferController` 注入，本视图不直接访问服务层。
final class TransferPaneView: MenuPanelPaneView {

    // MARK: 回调

    /// 点「刷新」重新发现
    var onRefresh: (() -> Void)?
    /// 点击设备行
    var onSelectDevice: ((RemoteDevice) -> Void)?
    /// 拖入 / 选择文件后发送
    var onDropFiles: (([URL]) -> Void)?
    /// 点击任务行（取消）
    var onCancelSession: ((String) -> Void)?
    /// 移除任务：第二参数为 true 表示同时删除落盘文件
    var onDismissSession: ((String, Bool) -> Void)?
    /// 点击「选择文件…」
    var onPickFiles: (() -> Void)?
    /// 点击「扫码接收」（打开二维码弹窗）
    var onOpenScanReceive: (() -> Void)?
    /// 点击免配对状态行 / 齿轮（打开设置）
    var onOpenSettings: (() -> Void)?

    // MARK: 子视图

    /// 页头行 — 与其余四页同一件（22pt）
    private let headerView = PaneHeaderRowView(title: "传送")
    /// 页脚状态带 — 与其余四页同壳（20pt）
    private let stateBand = PaneStateBandView()
    private let autoAcceptRow: MenuPanelKeyValueRow
    private let scanRow: MenuPanelKeyValueRow
    private let deviceHeader = MenuPanelHeaderRow(title: "附近设备", trailing: "未启动")
    private let deviceStack = NSStackView()
    private let emptyView = NSStackView()
    private let hintLabel = MenuPanelLabel.text("", font: PaneCardStyle.metaFont,
                                                color: PaneCardStyle.secondaryText)
    private let taskHeader = MenuPanelHeaderRow(title: "传输任务", trailing: "0 个")
    private let taskStack = NSStackView()
    private let dropHintRow: MenuPanelKeyValueRow

    // MARK: 状态

    /// 面板是否可见（由 `MenuPanelController` 装配时注入：popover.isShown）
    ///
    /// 默认 true＝被视为可见：未注入时宁可多刷一次，也不让状态带停在旧值。
    /// 收起时 `TransferController` 只更新模型、不推视图，避免每秒白跑一次布局。
    var isPanelVisible: () -> Bool = { true }

    private var devices: [RemoteDevice] = []
    private var sessions: [TransferSession] = []
    private var deviceRows: [MenuPanelTransferDeviceRow] = []
    private var taskRows: [MenuPanelTransferTaskRow] = []
    private var selectedDeviceId: String?
    private var isDragHighlighted = false
    /// 签名用于跳过无变化的列表重建
    private var deviceSignature = ""
    private var sessionSignature = ""
    /// 页脚状态带签名（与上面两个同源手法：内容没变就不重建/不重设文本）
    private var bandSignature = ""

    // MARK: - 初始化

    init() {
        dropHintRow = MenuPanelKeyValueRow(symbol: "square.and.arrow.down", title: "选择文件…",
                                          value: "或拖入",
                                          valueColor: MenuPanelStyle.accentColor,
                                          titleColor: .labelColor)
        autoAcceptRow = MenuPanelKeyValueRow(symbol: "lock.open", title: "免配对窗口", value: "")
        scanRow = MenuPanelKeyValueRow(symbol: "qrcode", title: "扫码接收", value: "手机直传",
                                       valueColor: MenuPanelStyle.accentColor,
                                       titleColor: .labelColor)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        registerForDraggedTypes([.fileURL])

        for stack in [deviceStack, taskStack] {
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 0
        }
        buildEmptyView()
        hintLabel.isHidden = true

        deviceHeader.onClick = { [weak self] in self?.onRefresh?() }
        dropHintRow.onClick = { [weak self] in self?.onPickFiles?() }
        scanRow.onClick = { [weak self] in self?.onOpenScanReceive?() }
        autoAcceptRow.onClick = { [weak self] in self?.onOpenSettings?() }
        autoAcceptRow.isHidden = true

        let stack = NSStackView(views: [headerView, autoAcceptRow, scanRow, deviceHeader, deviceStack,
                                        emptyView, hintLabel, taskHeader, taskStack, dropHintRow,
                                        MenuPanelLabel.spacer(), stateBand])
        stack.orientation = .vertical
        stack.alignment = .leading
        // 主栈间距统一到令牌档（原 6pt 是这一页独有的取值）
        stack.spacing = PaneCardStyle.cardSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for subview in stack.arrangedSubviews {
            subview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        // 首次上屏就给一条有内容的状态带：等第一帧数据前它也不该是空灰条
        updateBand(devices: [], sessions: [], autoAcceptText: "", statusText: "未启动")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 键盘可达行：设备行 → 任务行 → 选择文件
    override var focusableRows: [MenuPanelRow] {
        (autoAcceptRow.isHidden ? [] : [autoAcceptRow]) + [scanRow] + deviceRows + taskRows + [dropHintRow]
    }

    // MARK: - 空态

    private func buildEmptyView() {
        emptyView.orientation = .vertical
        emptyView.alignment = .centerX
        emptyView.spacing = 4

        if let icon = MenuPanelLabel.symbol("antenna.radiowaves.left.and.right",
                                            pointSize: 26, color: MenuPanelStyle.tertiaryText) {
            emptyView.addArrangedSubview(icon)
        }
        let title = MenuPanelLabel.text("正在搜索局域网设备",
                                        font: PaneCardStyle.rowNameFont)
        title.alignment = .center
        emptyView.addArrangedSubview(title)
        let hint = MenuPanelLabel.text("同一 Wi-Fi 下的手机与 Mac 会自动出现",
                                       font: PaneCardStyle.metaFont,
                                       color: PaneCardStyle.tertiaryText)
        hint.alignment = .center
        emptyView.addArrangedSubview(hint)
    }

    // MARK: - 数据更新

    /// 刷新设备与任务列表
    ///
    /// - Parameters:
    ///   - autoAcceptText: 免配对窗口剩余时间（空串 = 未开启，隐藏状态行）
    ///   - autoAcceptActive: 是否处于免配对窗口内（决定高亮色）
    func update(devices newDevices: [RemoteDevice], sessions newSessions: [TransferSession],
                selectedDeviceId newSelected: String?, statusText: String,
                autoAcceptText: String, autoAcceptActive: Bool) {
        devices = newDevices
        sessions = newSessions
        selectedDeviceId = newSelected
        autoAcceptRow.isHidden = autoAcceptText.isEmpty
        if !autoAcceptText.isEmpty {
            autoAcceptRow.updateValue("免配对 \(autoAcceptText)",
                                      color: autoAcceptActive ? .systemOrange : MenuPanelStyle.secondaryText)
        }

        deviceHeader.updateTrailing(newDevices.isEmpty ? statusText : "\(newDevices.count) 台 · 刷新")
        updateBand(devices: newDevices, sessions: newSessions,
                   autoAcceptText: autoAcceptText, statusText: statusText)

        let devicePad = newDevices.map { "\($0.deviceId):\($0.alias):\($0.isOnline):\($0.isPaired)" }
            .joined(separator: "|")
        if devicePad != deviceSignature {
            deviceSignature = devicePad
            rebuildDeviceRows()
        } else {
            for row in deviceRows { row.updateSelectedIndex(selectedDeviceId) }
        }
        emptyView.isHidden = !newDevices.isEmpty

        // 任务行只在会话集合变化时重建；进度变化走行内插值，避免每帧重建导致闪烁
        let sessionIdPad = newSessions.prefix(4).map(\.id).joined(separator: "|")
        taskHeader.updateTrailing(newSessions.isEmpty ? "0 个" : "\(newSessions.count) 个")
        if sessionIdPad != sessionSignature {
            sessionSignature = sessionIdPad
            rebuildTaskRows()
        } else {
            for (row, session) in zip(taskRows, newSessions.prefix(4)) {
                row.update(session: session)
            }
        }
    }

    /// 页脚状态带 — 发现状态 / 设备 / 任务 / 免配对窗口
    ///
    /// 只放本帧真实数据：空集合的项直接不出现，不写「0 个」冒充读数。
    /// 「发现」一项始终在：没有设备时它承载「未启动 / 搜索中」这类过程状态，
    /// 否则空态下页脚会是一条什么都没有的灰条。
    private func updateBand(devices: [RemoteDevice], sessions: [TransferSession],
                            autoAcceptText: String, statusText: String) {
        let active = sessions.filter { $0.state.isActive }.count
        // 签名覆盖状态带的全部可见项：设备 / 任务 / 进行中 / 免配对倒计时 / 发现状态。
        // 键与值都进签名，避免「数值变了但条数没变」被误判为无变化。
        let signature = TransferBandSignature.make(statusText: statusText,
                                                   deviceCount: devices.count,
                                                   sessionCount: sessions.count,
                                                   activeCount: active,
                                                   autoAcceptText: autoAcceptText)
        guard signature != bandSignature else { return }
        bandSignature = signature
        stateBand.update(items: [
            (key: "发现", value: statusText.isEmpty ? nil : statusText),
            (key: "设备", value: devices.isEmpty ? nil : "\(devices.count) 台"),
            (key: "任务", value: sessions.isEmpty ? nil : "\(sessions.count) 个"),
            (key: "进行中", value: active == 0 ? nil : "\(active) 个"),
            (key: "免配对", value: autoAcceptText.isEmpty ? nil : autoAcceptText),
        ])
    }

    /// 行内轻提示
    func showHint(_ message: String) {
        hintLabel.stringValue = message
        hintLabel.isHidden = message.isEmpty
    }

    private func rebuildDeviceRows() {
        for row in deviceRows {
            deviceStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        deviceRows = devices.map { device in
            let row = MenuPanelTransferDeviceRow(device: device,
                                                 selected: device.deviceId == selectedDeviceId)
            row.onClick = { [weak self] in self?.onSelectDevice?(device) }
            return row
        }
        for (index, row) in deviceRows.enumerated() {
            deviceStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: deviceStack.widthAnchor).isActive = true
            // 设备出现：淡入 + 上移 10px，逐项延迟 24ms（设计文档 §7.2）
            TransferMotion.fadeIn(row, offsetY: 10, delay: Double(index) * TransferMotion.stagger)
        }
    }

    private func rebuildTaskRows() {
        for row in taskRows {
            taskStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        taskRows = sessions.prefix(4).map { session in
            let row = MenuPanelTransferTaskRow(session: session)
            row.onClick = { [weak self] in self?.onCancelSession?(session.id) }
            row.onClickEnabled = session.state.isActive
            // 接收已完成的任务可拖出为真实文件
            if session.state == .completed, session.direction == .recv, let directory = session.directory {
                row.draggableFileURLs = session.files
                    .map { directory.appendingPathComponent($0.name) }
                    .filter { FileManager.default.fileExists(atPath: $0.path) }
            }
            row.allowsDismiss = session.state.isTerminal
            row.onDismiss = { [weak self] deleteFiles in
                self?.onDismissSession?(session.id, deleteFiles)
            }
            return row
        }
        for (index, row) in taskRows.enumerated() {
            taskStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: taskStack.widthAnchor).isActive = true
            TransferMotion.fadeIn(row, offsetY: 6, delay: Double(index) * TransferMotion.stagger)
        }
    }

    // MARK: - 拖拽

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self],
                                                      options: [.urlReadingFileURLsOnly: true]) else {
            return []
        }
        isDragHighlighted = true
        needsDisplay = true
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        isDragHighlighted = false
        needsDisplay = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDragHighlighted = false
        needsDisplay = true
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                              options: options) as? [URL],
              !urls.isEmpty else { return false }
        onDropFiles?(urls)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        if isDragHighlighted {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2),
                                    xRadius: PaneCardStyle.cardRadius,
                                    yRadius: PaneCardStyle.cardRadius)
            path.lineWidth = 2
            path.setLineDash([5, 4], count: 2, phase: 0)
            MenuPanelStyle.accentColor.setStroke()
            path.stroke()
        }
        super.draw(dirtyRect)
    }
}
