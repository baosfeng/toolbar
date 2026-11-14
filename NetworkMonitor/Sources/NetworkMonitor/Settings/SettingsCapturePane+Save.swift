import AppKit
import NetworkMonitorCore

// MARK: - 保存卡（自动保存 / 输出格式 / JPEG 质量 / 快速保存目录）

/// 「截图与贴图」页的保存卡片 —— 从主文件拆出，守住单文件体积门禁
///
/// 四行都只写偏好，消费方分别是：
/// - 复制后自动保存 → SnipController.overlayView(_:didConfirm:)
/// - 输出格式 / JPEG 质量 → SnipController.saveFormat / jpegQuality（快速保存、自动保存、另存为、贴图保存共用）
/// - 快速保存目录 → SnipSaveDirectory.resolvedQuickSaveDirectory
extension SettingsCapturePane {

    func buildSaveSection() {
        let autoSave = NSSwitch()
        autoSave.target = self
        autoSave.action = #selector(autoSaveChanged)
        autoSave.setAccessibilityLabel("复制后自动保存")
        autoSaveSwitch = autoSave
        let autoSaveRow = SettingsRowView(title: "复制后自动保存",
                                          subtitle: "截图复制到剪贴板时同时落盘（格式跟随下一行）")
        autoSaveRow.trailingStack.addArrangedSubview(autoSave)

        directoryRow.update(subtitle: quickSaveDirectorySubtitle())
        directoryRow.trailingStack.addArrangedSubview(
            SettingsLinkButton.make("选择…", target: self, action: #selector(chooseQuickSaveDirectory)))
        directoryRow.trailingStack.addArrangedSubview(
            SettingsLinkButton.make("打开", target: self, action: #selector(openQuickSaveFolder)))

        // 输出格式：PNG（无损）/ JPEG（体积小，质量可调）
        let formatControl = NSSegmentedControl(labels: SnipImageFormat.allCases.map(\.displayName),
                                               trackingMode: .selectOne,
                                               target: self,
                                               action: #selector(saveFormatChanged))
        formatControl.controlSize = .small
        formatControl.font = SettingsTheme.rowTitleFont
        formatControl.setAccessibilityLabel("截图输出格式")
        SettingsControlChrome.applyStandardHeight(to: formatControl)
        saveFormatControl = formatControl
        let formatRow = SettingsRowView(title: "输出格式")
        formatRow.trailingStack.addArrangedSubview(formatControl)

        let quality = NSSlider(value: SnipImageFormat.defaultJPEGQuality,
                               minValue: SnipImageFormat.jpegQualityRange.lowerBound,
                               maxValue: SnipImageFormat.jpegQualityRange.upperBound,
                               target: self,
                               action: #selector(jpegQualityChanged))
        quality.isContinuous = true
        quality.widthAnchor.constraint(equalToConstant: 140).isActive = true
        quality.setAccessibilityLabel("JPEG 质量")
        jpegQualitySlider = quality
        let qualityValue = MenuPanelLabel.text("90%", font: SettingsTheme.rowValueFont,
                                               color: SettingsTheme.textSecondary)
        qualityValue.alignment = .right
        qualityValue.widthAnchor.constraint(equalToConstant: 44).isActive = true
        qualityValue.setContentHuggingPriority(.required, for: .horizontal)
        qualityValue.setContentCompressionResistancePriority(.required, for: .horizontal)
        jpegQualityLabel = qualityValue
        let qualityStack = NSStackView(views: [quality, qualityValue])
        qualityStack.orientation = .horizontal
        qualityStack.alignment = .centerY
        qualityStack.spacing = 8
        let qualityRow = SettingsRowView(title: "JPEG 质量",
                                         subtitle: "仅 JPEG 生效：数值越高越清晰、文件越大")
        qualityRow.trailingStack.addArrangedSubview(qualityStack)

        let card = SettingsCardView()
        card.addRow(autoSaveRow)
        card.addRow(formatRow)
        card.addRow(qualityRow)
        card.addRow(directoryRow)
        page.addCard(card, sectionTitle: "保存")
    }

    // MARK: - 刷新

    /// 同步格式控件与 JPEG 质量（PNG 档下质量滑块显灰，避免「调了没反应」）
    func refreshSaveFormat() {
        let format = SnipImageFormat.resolved(raw: storage.string(forKey: SnipPreferenceKey.saveFormat))
        if let index = SnipImageFormat.allCases.firstIndex(of: format) {
            saveFormatControl?.selectedSegment = index
        }
        let quality = SnipImageFormat.clampedQuality(
            storage.object(forKey: SnipPreferenceKey.jpegQuality) as? Double
                ?? SnipImageFormat.defaultJPEGQuality)
        jpegQualitySlider?.doubleValue = quality
        jpegQualityLabel?.stringValue = "\(Int((quality * 100).rounded()))%"
        let isJPEG = format == .jpeg
        jpegQualitySlider?.isEnabled = isJPEG
        jpegQualityLabel?.textColor = isJPEG ? SettingsTheme.textSecondary : SettingsTheme.textTertiary
    }

    /// 快速保存目录行副标题：路径 + 来源（自定义 / 默认）
    func refreshQuickSaveDirectory() {
        directoryRow.update(subtitle: quickSaveDirectorySubtitle())
    }

    // MARK: - 动作

    @objc func saveFormatChanged() {
        let index = saveFormatControl?.selectedSegment ?? 0
        guard SnipImageFormat.allCases.indices.contains(index) else { return }
        let format = SnipImageFormat.allCases[index]
        storage.set(format.rawValue, forKey: SnipPreferenceKey.saveFormat)
        logger.info("截图输出格式：\(format.displayName)")
        refreshSaveFormat()
        refreshStatusChip()
    }

    @objc func jpegQualityChanged() {
        let value = SnipImageFormat.clampedQuality(jpegQualitySlider?.doubleValue
                                                    ?? SnipImageFormat.defaultJPEGQuality)
        storage.set(Double(value), forKey: SnipPreferenceKey.jpegQuality)
        jpegQualityLabel?.stringValue = "\(Int((value * 100).rounded()))%"
        refreshStatusChip()
    }

    @objc func autoSaveChanged() {
        let enabled = autoSaveSwitch?.state == .on
        storage.set(enabled, forKey: SnipPreferenceKey.autoSaveAfterCopy)
        logger.info("截图自动保存：\(enabled ? "开" : "关")")
    }

    /// 选择快速保存目录 — 只写偏好，落盘时再解析
    @objc func chooseQuickSaveDirectory() {
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
        logger.info("快速保存目录已切换：\(LogRedaction.path(url.path))")
    }

    @objc func openQuickSaveFolder() {
        let directory = SnipSaveDirectory.resolvedQuickSaveDirectory(storage: storage)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    // MARK: - 工具

    func quickSaveDirectorySubtitle() -> String {
        let directory = SnipSaveDirectory.resolvedQuickSaveDirectory(storage: storage)
        let source = SnipSaveDirectory.customPath(storage: storage) == nil ? "默认" : "自定义"
        return "\(Self.displayPath(directory)) · \(source)"
    }

    static func displayPath(_ url: URL) -> String {
        url.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path,
                                      with: "~")
    }
}
