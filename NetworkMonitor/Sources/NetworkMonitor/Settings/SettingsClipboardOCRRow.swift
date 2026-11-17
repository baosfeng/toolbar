import AppKit
import NetworkMonitorCore

// MARK: - 剪贴板设置页的识别开关

/// 「识别图片中文字」设置行 — 控件、动作与刷新口径收在一处，单独成文件
///
/// 开关只写偏好：采集回调与识别调度每次现读，关掉后新条目不再识别、已有结果原样保留。
@MainActor
final class SettingsClipboardOCRRow {

    /// 行标题（写明本地识别，不让用户去猜是否联网）
    static let title = "识别图片中文字（本地识别，结果可搜索）"

    private let toggle = NSSwitch()
    private let preferences: ClipboardPreferences
    private let logger: LoggingService

    init(preferences: ClipboardPreferences, logger: LoggingService) {
        self.preferences = preferences
        self.logger = logger
        toggle.target = self
        toggle.action = #selector(changed)
        toggle.setAccessibilityLabel("识别图片中文字")
    }

    /// 设置页构建时插进「采集」卡的一行
    var row: SettingsRowView {
        let row = SettingsRowView(title: Self.title)
        row.trailingStack.addArrangedSubview(toggle)
        return row
    }

    /// 设置页刷新时回读偏好（真源始终是偏好，不在这里缓存状态）
    func refresh() {
        toggle.state = preferences.imageOCRRecognizeEnabled ? .on : .off
    }

    @objc private func changed() {
        preferences.imageOCRRecognizeEnabled = toggle.state == .on
        logger.info("剪贴板图片文字识别开关更新：\(preferences.imageOCRRecognizeEnabled)")
    }
}
