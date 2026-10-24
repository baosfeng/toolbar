import AppKit
import NetworkMonitorCore

// MARK: - 截图与贴图设置

/// 设置项存储键 — 集中定义，避免散落在各处
public enum SnipPreferenceKey {
    public static let autoSaveAfterCopy = "snip.autoSaveAfterCopy"
    public static let pinDefaultAlpha = "snip.pinDefaultAlpha"
    public static let annotationColor = "snip.annotationColor"
    public static let annotationLineWidth = "snip.annotationLineWidth"
}

/// 截图 / 贴图 / 标注 / 控制 四组设置 — 单页纵向分组，避免多页签的导航成本
@MainActor
final class SnipSettingsWindow: NSObject, NSWindowDelegate {

    private let window: NSWindow
    private let storage: KeyValueStorage
    private let logger: LoggingService
    private let hotKeySummary: () -> String

    private var autoSaveSwitch: NSButton?
    private var alphaSlider: NSSlider?
    private var alphaLabel: NSTextField?
    private var colorButtons: [NSButton] = []
    private var widthControl: NSSegmentedControl?

    init(storage: KeyValueStorage = AppContext.shared.storage,
         logger: LoggingService = AppContext.shared.logger,
         hotKeySummary: @escaping () -> String) {
        self.storage = storage
        self.logger = logger
        self.hotKeySummary = hotKeySummary
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
                          styleMask: [.titled, .closable],
                          backing: .buffered,
                          defer: false)
        super.init()
        window.title = "截图与贴图设置"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = buildContent()
    }

    func show() {
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        // 菜单栏 App 是 accessory 激活策略，普通窗口不主动前置会藏在别的窗口后面
        window.level = .floating
        window.orderFrontRegardless()
        window.makeKey()
    }

    // MARK: - 界面

    private func buildContent() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(sectionTitle("截屏"))
        let autoSave = NSButton(checkboxWithTitle: "复制后同时自动保存到快速保存目录",
                                target: self,
                                action: #selector(autoSaveChanged))
        autoSaveSwitch = autoSave
        stack.addArrangedSubview(autoSave)

        let directoryRow = NSStackView()
        directoryRow.orientation = .horizontal
        directoryRow.spacing = 8
        let directoryLabel = NSTextField(labelWithString: "快速保存目录：")
        directoryLabel.font = .systemFont(ofSize: 12)
        let pathLabel = NSTextField(labelWithString: SnipFileNaming.quickSaveDirectory().path)
        pathLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        let openButton = NSButton(title: "打开", target: self, action: #selector(openQuickSaveFolder))
        openButton.bezelStyle = .rounded
        directoryRow.addArrangedSubview(directoryLabel)
        directoryRow.addArrangedSubview(pathLabel)
        directoryRow.addArrangedSubview(openButton)
        pathLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(directoryRow)

        stack.addArrangedSubview(spacer())
        stack.addArrangedSubview(sectionTitle("贴图"))
        let alphaRow = NSStackView()
        alphaRow.orientation = .horizontal
        alphaRow.spacing = 8
        let alphaTitle = NSTextField(labelWithString: "默认不透明度")
        alphaTitle.font = .systemFont(ofSize: 12)
        let slider = NSSlider(value: 1, minValue: 0.3, maxValue: 1, target: self, action: #selector(alphaChanged))
        slider.isContinuous = true
        slider.widthAnchor.constraint(equalToConstant: 220).isActive = true
        alphaSlider = slider
        let valueLabel = NSTextField(labelWithString: "100%")
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        valueLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true
        alphaLabel = valueLabel
        alphaRow.addArrangedSubview(alphaTitle)
        alphaRow.addArrangedSubview(slider)
        alphaRow.addArrangedSubview(valueLabel)
        stack.addArrangedSubview(alphaRow)

        stack.addArrangedSubview(spacer())
        stack.addArrangedSubview(sectionTitle("标注"))
        let colorRow = NSStackView()
        colorRow.orientation = .horizontal
        colorRow.spacing = 6
        let palette: [SnipAnnotationColor] = [.red, .orange, .yellow, .green, .blue, .black, .white]
        for color in palette {
            let button = NSButton(title: "", target: self, action: #selector(colorChanged(_:)))
            button.bezelStyle = .regularSquare
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 9
            button.layer?.backgroundColor = NSColor(cgColor: color.cgColor)?.cgColor
            button.tag = palette.firstIndex(of: color) ?? 0
            button.widthAnchor.constraint(equalToConstant: 22).isActive = true
            button.heightAnchor.constraint(equalToConstant: 22).isActive = true
            colorButtons.append(button)
            colorRow.addArrangedSubview(button)
        }
        stack.addArrangedSubview(colorRow)

        let widthRow = NSStackView()
        widthRow.orientation = .horizontal
        widthRow.spacing = 8
        let widthTitle = NSTextField(labelWithString: "默认线宽")
        widthTitle.font = .systemFont(ofSize: 12)
        let segmented = NSSegmentedControl(labels: ["细", "中", "粗"],
                                           trackingMode: .selectOne,
                                           target: self,
                                           action: #selector(widthChanged))
        widthControl = segmented
        widthRow.addArrangedSubview(widthTitle)
        widthRow.addArrangedSubview(segmented)
        stack.addArrangedSubview(widthRow)

        stack.addArrangedSubview(spacer())
        stack.addArrangedSubview(sectionTitle("控制"))
        let hotKeys = NSTextField(labelWithString: hotKeySummary())
        hotKeys.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        hotKeys.textColor = .secondaryLabelColor
        stack.addArrangedSubview(hotKeys)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 560))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor)
        ])
        scroll.documentView = container
        container.frame = NSRect(x: 0, y: 0, width: 520, height: 560)
        return scroll
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func spacer() -> NSView {
        let view = NSView()
        view.heightAnchor.constraint(equalToConstant: 8).isActive = true
        return view
    }

    // MARK: - 状态同步

    private func refresh() {
        autoSaveSwitch?.state = storage.bool(forKey: SnipPreferenceKey.autoSaveAfterCopy) ? .on : .off
        let alpha = storage.object(forKey: SnipPreferenceKey.pinDefaultAlpha) as? Double ?? 1
        alphaSlider?.doubleValue = alpha
        alphaLabel?.stringValue = "\(Int(alpha * 100))%"
        let width = storage.object(forKey: SnipPreferenceKey.annotationLineWidth) as? Double ?? 3
        widthControl?.selectedSegment = width <= 2 ? 0 : (width >= 8 ? 2 : 1)
        let colorHex = storage.string(forKey: SnipPreferenceKey.annotationColor) ?? "#EB3330"
        for (index, button) in colorButtons.enumerated() {
            button.layer?.borderWidth = index == colorIndex(for: colorHex) ? 2 : 0
            button.layer?.borderColor = NSColor.controlAccentColor.cgColor
        }
    }

    private func colorIndex(for hex: String) -> Int {
        let palette = ["#EB3330", "#F58C24", "#FAD12E", "#33B859", "#2980F2", "#1A1A1A", "#FFFFFF"]
        return palette.firstIndex(of: hex.uppercased()) ?? 0
    }

    // MARK: - 动作

    @objc private func autoSaveChanged() {
        storage.set(autoSaveSwitch?.state == .on, forKey: SnipPreferenceKey.autoSaveAfterCopy)
        logger.info("自动保存：\(autoSaveSwitch?.state == .on ? "开" : "关")")
    }

    @objc private func alphaChanged() {
        let value = alphaSlider?.doubleValue ?? 1
        storage.set(Double(value), forKey: SnipPreferenceKey.pinDefaultAlpha)
        alphaLabel?.stringValue = "\(Int((value * 100).rounded()))%"
    }

    @objc private func colorChanged(_ sender: NSButton) {
        let palette = ["#EB3330", "#F58C24", "#FAD12E", "#33B859", "#2980F2", "#1A1A1A", "#FFFFFF"]
        guard palette.indices.contains(sender.tag) else { return }
        storage.set(palette[sender.tag], forKey: SnipPreferenceKey.annotationColor)
        refresh()
    }

    @objc private func widthChanged() {
        let widths: [Double] = [2, 4, 8]
        let index = widthControl?.selectedSegment ?? 1
        guard widths.indices.contains(index) else { return }
        storage.set(widths[index], forKey: SnipPreferenceKey.annotationLineWidth)
    }

    @objc private func openQuickSaveFolder() {
        let directory = SnipFileNaming.quickSaveDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }
}
