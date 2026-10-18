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
    /// 点击免配对状态行 / 齿轮（打开设置）
    var onOpenSettings: (() -> Void)?

    // MARK: 子视图

    private let autoAcceptRow: MenuPanelKeyValueRow
    private let deviceHeader = MenuPanelHeaderRow(title: "附近设备", trailing: "未启动")
    private let deviceStack = NSStackView()
    private let emptyView = NSStackView()
    private let hintLabel = MenuPanelLabel.text("", font: MenuPanelStyle.smallValueFont,
                                                color: MenuPanelStyle.secondaryText)
    private let taskHeader = MenuPanelHeaderRow(title: "传输任务", trailing: "0 个")
    private let taskStack = NSStackView()
    private let dropHintRow: MenuPanelKeyValueRow

    // MARK: 状态

    private var devices: [RemoteDevice] = []
    private var sessions: [TransferSession] = []
    private var deviceRows: [MenuPanelTransferDeviceRow] = []
    private var taskRows: [MenuPanelTransferTaskRow] = []
    private var selectedDeviceId: String?
    private var isDragHighlighted = false
    /// 签名用于跳过无变化的列表重建
    private var deviceSignature = ""
    private var sessionSignature = ""

    // MARK: - 初始化

    init() {
        dropHintRow = MenuPanelKeyValueRow(symbol: "square.and.arrow.down", title: "选择文件…", value: "或拖入")
        autoAcceptRow = MenuPanelKeyValueRow(symbol: "lock.open", title: "免配对窗口", value: "")
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
        autoAcceptRow.onClick = { [weak self] in self?.onOpenSettings?() }
        autoAcceptRow.isHidden = true

        let stack = NSStackView(views: [autoAcceptRow, deviceHeader, deviceStack, emptyView, hintLabel,
                                        taskHeader, taskStack, dropHintRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 键盘可达行：设备行 → 任务行 → 选择文件
    override var focusableRows: [MenuPanelRow] {
        (autoAcceptRow.isHidden ? [] : [autoAcceptRow]) + deviceRows + taskRows + [dropHintRow]
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
                                        font: NSFont.systemFont(ofSize: 12, weight: .regular))
        title.alignment = .center
        emptyView.addArrangedSubview(title)
        let hint = MenuPanelLabel.text("同一 Wi-Fi 下的手机与 Mac 会自动出现",
                                       font: NSFont.systemFont(ofSize: 10, weight: .regular),
                                       color: MenuPanelStyle.tertiaryText)
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
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8)
            path.lineWidth = 2
            path.setLineDash([5, 4], count: 2, phase: 0)
            MenuPanelStyle.accentColor.setStroke()
            path.stroke()
        }
        super.draw(dirtyRect)
    }
}
