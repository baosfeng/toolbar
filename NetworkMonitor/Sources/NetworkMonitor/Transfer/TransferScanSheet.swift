import AppKit
import NetworkMonitorCore

// MARK: - 扫码接收弹窗

/// 扫码接收弹窗 — 展示二维码、上传地址与 token 失效倒计时
///
/// 独立 `NSPanel`（菜单栏 popover 收起后仍可扫码）：层级 `.floating`，
/// 弹层动效沿用 `TransferMotion.popIn`（0.22s easeOut，减弱动态效果时直接落终态）。
@MainActor
final class TransferScanSheet {

    private var panel: NSPanel?
    private var countdownTimer: Timer?
    private var expiresAt: Date = .distantPast
    private let countdownLabel = NSTextField(labelWithString: "")
    private let addressLabel = NSTextField(labelWithString: "")

    /// 倒计时到期回调（UI 可提示重新生成）
    var onExpire: (() -> Void)?

    /// 是否正在显示
    var isVisible: Bool { panel?.isVisible ?? false }

    // MARK: - 展示

    func show(info: ScanSessionInfo, qrPNG: Data) {
        close()
        expiresAt = info.expiresAt

        let title = NSTextField(labelWithString: "用手机相机扫码，浏览器直接传文件")
        title.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        title.alignment = .center
        title.maximumNumberOfLines = 2
        title.lineBreakMode = .byWordWrapping

        let hint = NSTextField(labelWithString: "文件会保存到这台 Mac 的收件目录，无需安装 App")
        hint.font = NSFont.systemFont(ofSize: 12)
        hint.textColor = NSColor.labelColor.withAlphaComponent(0.72)
        hint.alignment = .center
        hint.maximumNumberOfLines = 2
        hint.lineBreakMode = .byWordWrapping

        let qrCard = makeQRCard(qrPNG: qrPNG)

        addressLabel.stringValue = info.url
        addressLabel.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
        addressLabel.textColor = NSColor.labelColor.withAlphaComponent(0.72)
        addressLabel.alignment = .center
        addressLabel.isSelectable = true
        addressLabel.lineBreakMode = .byTruncatingMiddle
        addressLabel.maximumNumberOfLines = 1
        addressLabel.setAccessibilityLabel("上传地址 \(info.url)")
        addressLabel.widthAnchor.constraint(equalToConstant: 276).isActive = true

        countdownLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        countdownLabel.textColor = .systemOrange
        countdownLabel.alignment = .center

        let closeButton = ClosureButton(title: "完成") { [weak self] in self?.close() }
        closeButton.keyEquivalent = "\u{1b}"
        closeButton.bezelStyle = .rounded
        closeButton.controlSize = .large
        closeButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        closeButton.heightAnchor.constraint(equalToConstant: 32).isActive = true
        closeButton.widthAnchor.constraint(equalToConstant: 276).isActive = true

        let stack = NSStackView(views: [title, hint, qrCard, addressLabel, countdownLabel, closeButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        if let icon = MenuPanelLabel.symbol("qrcode", pointSize: 22, color: .labelColor) {
            stack.insertArrangedSubview(icon, at: 0)
        }

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 420),
                            styleMask: [.titled, .closable],
                            backing: .buffered, defer: false)
        panel.title = "扫码接收"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.contentView = stack
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        TransferMotion.popIn(stack)
        startCountdown()
    }

    // MARK: - 关闭

    func close() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        guard let current = panel else { return }
        panel = nil
        guard current.isVisible, TransferMotion.isEnabled, let content = current.contentView else {
            current.orderOut(nil)
            return
        }
        TransferMotion.fadeOut(content) { current.orderOut(nil) }
    }

    // MARK: - 内部

    /// 二维码卡片 — 必须白底黑码才能被相机识别（深色模式下也不跟随系统色）
    private func makeQRCard(qrPNG: Data) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.white.cgColor
        card.layer?.cornerRadius = 12
        card.translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.image = NSImage(data: qrPNG)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.setAccessibilityLabel("扫码接收二维码")
        card.addSubview(imageView)

        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: 200),
            card.heightAnchor.constraint(equalToConstant: 200),
            imageView.widthAnchor.constraint(equalToConstant: 176),
            imageView.heightAnchor.constraint(equalToConstant: 176),
            imageView.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: card.centerYAnchor),
        ])
        return card
    }

    private func startCountdown() {
        countdownTimer?.invalidate()
        updateCountdown()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tickCountdown() }
        }
    }

    private func tickCountdown() {
        guard expiresAt > Date() else {
            countdownTimer?.invalidate()
            countdownTimer = nil
            countdownLabel.stringValue = "二维码已失效，请重新打开「扫码接收」"
            countdownLabel.textColor = .systemRed
            onExpire?()
            return
        }
        updateCountdown()
    }

    private func updateCountdown() {
        let remaining = max(0, Int(expiresAt.timeIntervalSinceNow.rounded(.up)))
        let minutes = remaining / 60
        let seconds = remaining % 60
        if minutes > 0 {
            countdownLabel.stringValue = "还有 \(minutes) 分 \(String(format: "%02d", seconds)) 秒失效"
        } else {
            countdownLabel.stringValue = "还有 \(seconds) 秒失效"
        }
        countdownLabel.textColor = remaining <= 60 ? .systemRed : .systemOrange
    }
}
