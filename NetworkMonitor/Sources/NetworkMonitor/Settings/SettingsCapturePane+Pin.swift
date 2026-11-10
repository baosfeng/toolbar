import AppKit
import NetworkMonitorCore

// MARK: - 贴图内容源与恢复池设置行

/// 「截图与贴图」页里贴图卡片的两行 — 从主文件拆出，守住单文件体积门禁
///
/// 两行都只写偏好，消费方分别在：
/// - 图片文件优先显示图像 → `SnipController+Pin.swift` 的 `pinFileContent`
/// - 可被恢复的已关闭贴图数 → `PinWindowController.recoverableCount`
extension SettingsCapturePane {

    /// 往贴图卡片追加内容源开关与恢复池上限两行（在 `buildPinSection` 里调用）
    func addPinContentSourceRows(to card: SettingsCardView) {
        let displayImageFiles = NSSwitch()
        displayImageFiles.target = self
        displayImageFiles.action = #selector(displayImageFilesChanged)
        displayImageFiles.setAccessibilityLabel("图片文件贴图时优先显示图像")
        displayImageFilesSwitch = displayImageFiles
        let displayImageFilesRow = SettingsRowView(
            title: "图片文件优先显示图像",
            subtitle: "关闭后，剪贴板里的图片文件直接以路径文本贴出")
        displayImageFilesRow.trailingStack.addArrangedSubview(displayImageFiles)
        card.addRow(displayImageFilesRow)

        let recoverable = NSPopUpButton(frame: .zero, pullsDown: false)
        recoverable.controlSize = .small
        recoverable.target = self
        recoverable.action = #selector(recoverableCountChanged)
        recoverable.setAccessibilityLabel("可被恢复的已关闭贴图数")
        for count in SnipClosedPinLimit.range {
            recoverable.addItem(withTitle: "\(count) 张")
        }
        recoverable.widthAnchor.constraint(equalToConstant: 78).isActive = true
        recoverablePopup = recoverable
        let recoverableRow = SettingsRowView(
            title: "可被恢复的已关闭贴图数",
            subtitle: "被关闭的贴图再按贴图键可以恢复，超出这个数后最早一张失效")
        recoverableRow.trailingStack.addArrangedSubview(recoverable)
        card.addRow(recoverableRow)
    }

    /// 同步两行控件状态（`refresh()` 里调用）
    func refreshPinContentSource() {
        // 默认开：键不存在时偏好看作「优先显示图像」
        displayImageFilesSwitch?.state =
            (storage.object(forKey: SnipPreferenceKey.pinDisplayImageFiles) == nil
                || storage.bool(forKey: SnipPreferenceKey.pinDisplayImageFiles)) ? .on : .off
        let recoverable = SnipClosedPinLimit.normalized(
            storage.integer(forKey: SnipPreferenceKey.pinRecoverableCount))
        recoverablePopup?.selectItem(withTitle: "\(recoverable) 张")
    }

    // MARK: - 动作

    @objc func displayImageFilesChanged() {
        let enabled = displayImageFilesSwitch?.state == .on
        storage.set(enabled, forKey: SnipPreferenceKey.pinDisplayImageFiles)
        logger.info("图片文件贴图优先显示图像：\(enabled ? "开" : "关")")
    }

    @objc func recoverableCountChanged() {
        let title = recoverablePopup?.titleOfSelectedItem ?? ""
        let count = SnipClosedPinLimit.normalized(Int(title.prefix { $0.isNumber }) ?? 0)
        storage.set(count, forKey: SnipPreferenceKey.pinRecoverableCount)
        logger.info("可被恢复的已关闭贴图数：\(count) 张")
    }
}
