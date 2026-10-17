import AppKit
import NetworkMonitorCore

// MARK: - 系统页

/// 系统页 — IP 地址、Wi-Fi 名称、开机自启动（可点切换）、退出（⌘Q）
final class SystemPaneView: MenuPanelPaneView {

    /// 点击「开机自启动」（由控制器执行 SMAppService 注册/注销）
    var onToggleLaunchAtStartup: (() -> Void)?
    /// 点击「退出」
    var onQuit: (() -> Void)?

    private let ipRow = MenuPanelKeyValueRow(symbol: "network", title: "IP 地址", value: "—")
    private let wifiRow = MenuPanelKeyValueRow(symbol: "wifi", title: "Wi-Fi", value: "—")
    private let launchRow: MenuPanelToggleRow
    private let quitRow: MenuPanelKeyValueRow

    // MARK: - 初始化

    init() {
        launchRow = MenuPanelToggleRow(title: "开机自启动", isOn: false, onToggle: {})
        quitRow = MenuPanelKeyValueRow(symbol: "power", title: "退出", value: "⌘Q", onClick: {})
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        launchRow.onClick = { [weak self] in self?.onToggleLaunchAtStartup?() }
        quitRow.onClick = { [weak self] in self?.onQuit?() }

        let stack = NSStackView(views: [ipRow, wifiRow, launchRow, quitRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
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

    /// 键盘可达行：开机自启动 → 退出
    override var focusableRows: [MenuPanelRow] { [launchRow, quitRow] }

    // MARK: - 数据更新

    /// 更新系统信息（文案由调用方决定，空值显示占位）
    func update(ip: String, wifi: String, launchAtStartup: Bool) {
        ipRow.updateValue(ip.isEmpty ? "未连接" : ip)
        wifiRow.updateValue(wifi.isEmpty ? "未连接" : wifi)
        launchRow.update(isOn: launchAtStartup)
    }
}
