import AppKit
import NetworkMonitorCore

// MARK: - 截图与贴图设置页

/// 截图与贴图设置 — 标注默认值、贴图不透明度与保存行为
///
/// 迁移自已下线的 `SnipSettingsWindow`：存储键沿用 `SnipPreferenceKey`，老设置继续生效。
/// 快速保存目录可自定义（偏好 `snip.quickSaveDirectoryPath`），未自定义时回落到默认目录。
final class SettingsCapturePane: SettingsPaneView {

    private let storage: any KeyValueStorage
    private let logger: LoggingService
    /// 只读的截图热键摘要（组合根注入；nil 时不显示「控制」分组）
    private let hotKeySummary: (() -> String)?
    private var hotKeyRow: SettingsRowView?

    /// 快速保存目录行（副标题随偏好变化，需要刷新）
    private let directoryRow = SettingsRowView(title: "快速保存目录")
    private var autoSaveSwitch: NSSwitch?
    private var alphaSlider: NSSlider?
    private var alphaValueLabel: NSTextField?
    private var widthControl: NSSegmentedControl?
    private var colorButtons: [NSButton] = []

    /// 标注调色板 — hex 与 `SnipAnnotationColor` 一一对应（偏好里存 hex）
    private static let palette: [(hex: String, color: SnipAnnotationColor, name: String)] = [
        ("#EB3330", .red, "红色"),
        ("#F58C24", .orange, "橙色"),
        ("#FAD12E", .yellow, "黄色"),
        ("#33B859", .green, "绿色"),
        ("#2980F2", .blue, "蓝色"),
        ("#1A1A1A", .black, "黑色"),
        ("#FFFFFF", .white, "白色"),
    ]

    private static let defaultColorHex = "#EB3330"

    init(storage: any KeyValueStorage = AppContext.shared.storage,
         hotKeySummary: (() -> String)? = nil,
         logger: LoggingService = AppContext.shared.logger) {
        self.storage = storage
        self.hotKeySummary = hotKeySummary
        self.logger = logger
        super.init(section: .capture)
    }

    // MARK: - 构建

    override func buildContent() {
        buildAnnotationSection()
        buildPinSection()
        buildSaveSection()
        buildHotKeySection()
        page.addNote("「选择…」切换快速保存目录后只影响之后的截图落盘，已保存的文件不会迁移；"
                     + "标注默认颜色与线宽对新截图生效。")
    }

    private func buildAnnotationSection() {
        buildColorButtons()
        let swatches = NSStackView()
        swatches.orientation = .horizontal
        swatches.alignment = .centerY
        swatches.spacing = 6
        colorButtons.forEach(swatches.addArrangedSubview)
        let colorRow = SettingsRowView(title: "默认颜色")
        colorRow.trailingStack.addArrangedSubview(swatches)

        let width = NSSegmentedControl(labels: ["细", "中", "粗"], trackingMode: .selectOne,
                                       target: self, action: #selector(widthChanged))
        width.controlSize = .small
        width.setAccessibilityLabel("标注默认线宽")
        widthControl = width
        let widthRow = SettingsRowView(title: "线宽")
        widthRow.trailingStack.addArrangedSubview(width)

        let card = SettingsCardView()
        card.addRow(colorRow)
        card.addRow(widthRow)
        page.addCard(card, sectionTitle: "标注")
    }

    private func buildPinSection() {
        let slider = NSSlider(value: 1, minValue: 0.3, maxValue: 1,
                              target: self, action: #selector(alphaChanged))
        slider.isContinuous = true
        slider.widthAnchor.constraint(equalToConstant: 140).isActive = true
        slider.setAccessibilityLabel("贴图默认不透明度")
        alphaSlider = slider

        let value = MenuPanelLabel.text("100%", font: SettingsStyle.rowValueFont,
                                        color: .secondaryLabelColor)
        value.alignment = .right
        value.widthAnchor.constraint(equalToConstant: 44).isActive = true
        value.setContentHuggingPriority(.required, for: .horizontal)
        value.setContentCompressionResistancePriority(.required, for: .horizontal)
        alphaValueLabel = value

        let stack = NSStackView(views: [slider, value])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        let row = SettingsRowView(title: "默认不透明度")
        row.trailingStack.addArrangedSubview(stack)

        let card = SettingsCardView()
        card.addRow(row)
        page.addCard(card, sectionTitle: "贴图")
    }

    private func buildSaveSection() {
        let autoSave = NSSwitch()
        autoSave.target = self
        autoSave.action = #selector(autoSaveChanged)
        autoSave.setAccessibilityLabel("复制后自动保存")
        autoSaveSwitch = autoSave
        let autoSaveRow = SettingsRowView(title: "复制后自动保存",
                                          subtitle: "截图复制到剪贴板时同时落盘为 PNG")
        autoSaveRow.trailingStack.addArrangedSubview(autoSave)

        directoryRow.update(subtitle: quickSaveDirectorySubtitle())
        directoryRow.trailingStack.addArrangedSubview(
            SettingsLinkButton.make("选择…", target: self, action: #selector(chooseQuickSaveDirectory)))
        directoryRow.trailingStack.addArrangedSubview(
            SettingsLinkButton.make("打开", target: self, action: #selector(openQuickSaveFolder)))

        let card = SettingsCardView()
        card.addRow(autoSaveRow)
        card.addRow(directoryRow)
        page.addCard(card, sectionTitle: "保存")
    }

    /// 调色板色块 — 22pt 圆形；选中态 2pt 强调色描边，未选中 1pt 分隔线（白色块在浅色下可见）
    private func buildColorButtons() {
        for (index, entry) in Self.palette.enumerated() {
            let button = NSButton(title: "", target: self, action: #selector(colorChanged(_:)))
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 11
            button.layer?.backgroundColor = NSColor(srgbRed: entry.color.red,
                                                    green: entry.color.green,
                                                    blue: entry.color.blue,
                                                    alpha: entry.color.alpha).cgColor
            button.tag = index
            button.widthAnchor.constraint(equalToConstant: 22).isActive = true
            button.heightAnchor.constraint(equalToConstant: 22).isActive = true
            button.setAccessibilityLabel("标注默认颜色：\(entry.name)")
            colorButtons.append(button)
        }
    }

    /// 控制 — 只读的截图 / 贴图热键摘要（旧窗口「控制」组，信息项不是设置）
    private func buildHotKeySection() {
        guard let summary = hotKeySummary else { return }
        let row = SettingsRowView(title: "快捷键", subtitle: summary())
        hotKeyRow = row
        let card = SettingsCardView()
        card.addRow(row)
        page.addCard(card, sectionTitle: "控制")
    }

    // MARK: - 刷新

    override func refresh() {
        autoSaveSwitch?.state = storage.bool(forKey: SnipPreferenceKey.autoSaveAfterCopy) ? .on : .off

        let alpha = min(max(storage.object(forKey: SnipPreferenceKey.pinDefaultAlpha) as? Double ?? 1, 0.3), 1)
        alphaSlider?.doubleValue = alpha
        alphaValueLabel?.stringValue = "\(Int((alpha * 100).rounded()))%"

        let lineWidth = storage.object(forKey: SnipPreferenceKey.annotationLineWidth) as? Double ?? 3
        widthControl?.selectedSegment = lineWidth <= 2 ? 0 : (lineWidth >= 8 ? 2 : 1)

        refreshQuickSaveDirectory()
        updateColorSelection()
        if let text = hotKeySummary?() { hotKeyRow?.update(subtitle: text) }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColorSelection()
    }

    private func updateColorSelection() {
        let hex = storage.string(forKey: SnipPreferenceKey.annotationColor) ?? Self.defaultColorHex
        let selectedIndex = Self.palette.firstIndex { $0.hex.caseInsensitiveCompare(hex) == .orderedSame } ?? 0
        for (index, button) in colorButtons.enumerated() {
            let isSelected = index == selectedIndex
            button.layer?.borderWidth = isSelected ? 2 : 1
            button.layer?.borderColor = (isSelected ? SettingsStyle.accent : NSColor.separatorColor).cgColor
        }
    }

    // MARK: - 动作

    @objc private func autoSaveChanged() {
        let enabled = autoSaveSwitch?.state == .on
        storage.set(enabled, forKey: SnipPreferenceKey.autoSaveAfterCopy)
        logger.info("截图自动保存：\(enabled ? "开" : "关")")
    }

    @objc private func alphaChanged() {
        let value = alphaSlider?.doubleValue ?? 1
        storage.set(Double(value), forKey: SnipPreferenceKey.pinDefaultAlpha)
        alphaValueLabel?.stringValue = "\(Int((value * 100).rounded()))%"
    }

    @objc private func colorChanged(_ sender: NSButton) {
        guard Self.palette.indices.contains(sender.tag) else { return }
        storage.set(Self.palette[sender.tag].hex, forKey: SnipPreferenceKey.annotationColor)
        updateColorSelection()
    }

    @objc private func widthChanged() {
        let widths: [Double] = [2, 4, 8]
        let index = widthControl?.selectedSegment ?? 1
        guard widths.indices.contains(index) else { return }
        storage.set(Double(widths[index]), forKey: SnipPreferenceKey.annotationLineWidth)
    }

    /// 选择快速保存目录 — 只写偏好，落盘时再解析
    @objc private func chooseQuickSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "选择快速保存目录"
        panel.prompt = "选择"
        panel.directoryURL = SnipSaveDirectory.resolvedQuickSaveDirectory(storage: storage)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // 选中的就是默认目录时清掉自定义，免得副标题误标「自定义」
        let isDefault = url.standardizedFileURL
            == SnipFileNaming.quickSaveDirectory().standardizedFileURL
        SnipSaveDirectory.setCustomDirectory(isDefault ? nil : url, storage: storage)
        refreshQuickSaveDirectory()
        logger.info("快速保存目录已切换：\(url.path)")
    }

    @objc private func openQuickSaveFolder() {
        let directory = SnipSaveDirectory.resolvedQuickSaveDirectory(storage: storage)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    // MARK: - 工具

    /// 目录副标题：路径 + 来源（自定义 / 默认）
    private func quickSaveDirectorySubtitle() -> String {
        let directory = SnipSaveDirectory.resolvedQuickSaveDirectory(storage: storage)
        let source = SnipSaveDirectory.customPath(storage: storage) == nil ? "默认" : "自定义"
        return "\(Self.displayPath(directory)) · \(source)"
    }

    private func refreshQuickSaveDirectory() {
        directoryRow.update(subtitle: quickSaveDirectorySubtitle())
    }

    private static func displayPath(_ url: URL) -> String {
        url.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path,
                                      with: "~")
    }
}
