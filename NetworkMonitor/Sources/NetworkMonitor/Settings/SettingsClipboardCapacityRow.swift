import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign

// MARK: - 剪贴板设置页的「最大容量」行

/// 「最大容量」设置行 —— 与「最大条数」并列的另一维上限（按字节，而非按条数）
///
/// 单独成文件的原因：容量这一行自带输入校验、回读与副标题状态，塞进主文件会撑大
/// 既有同族合计（门禁只降不升）。控件与动作收在这里，主文件只负责把它插进「存储」卡。
///
/// 口径：偏好存字节、界面按 MB 编辑；0 = 不限。解析与校验在
/// `ClipboardCapacityUsage.parsedMegabytes`（Core 纯函数，可单测），这里只做回显与落偏好。
@MainActor
final class SettingsClipboardCapacityRow: NSObject, NSTextFieldDelegate {

    /// 与「最大条数」并列时用的行标题
    static let title = "最大容量"

    /// 默认副标题：说明超限后的行为
    static let subtitle = "超过后自动删除最旧条目（收藏与板内条目豁免）"

    /// 0 = 不限时改用的副标题
    static let unlimitedSubtitle = "0 = 不限（不按容量清理）"

    /// MB 与字节的换算基数（1 MB = 1024 × 1024 字节）
    static let bytesPerMegabyte: UInt64 = 1024 * 1024

    private let field = NSTextField()
    private let preferences: ClipboardPreferences
    private let logger: LoggingService
    /// 容量变更后通知宿主立即按新上限清一次（不等到下一次采集）
    private let onCommit: () -> Void
    private let rowView = SettingsRowView(title: SettingsClipboardCapacityRow.title,
                                          subtitle: SettingsClipboardCapacityRow.subtitle)

    init(preferences: ClipboardPreferences, logger: LoggingService, onCommit: @escaping () -> Void) {
        self.preferences = preferences
        self.logger = logger
        self.onCommit = onCommit
        super.init()
        configureField()
        rowView.trailingStack.addArrangedSubview(field)
        // 单位跟着输入框走，避免用户把它当成「条」来填
        rowView.trailingStack.addArrangedSubview(
            MenuPanelLabel.text("MB", font: SettingsTheme.rowSubtitleFont, color: SettingsTheme.textSecondary))
        refresh()
    }

    /// 插进「存储」卡的一行（与占用行上下相邻：一眼看到「现在多少 / 上限多少」）
    var row: SettingsRowView { rowView }

    private func configureField() {
        field.controlSize = .small
        field.alignment = .right
        field.font = SettingsTheme.rowValueFont
        field.target = self
        field.action = #selector(changed)
        field.delegate = self
        field.widthAnchor.constraint(equalToConstant: 64).isActive = true
        field.setAccessibilityLabel("最大容量（MB）")
        SettingsControlChrome.applyStandardHeight(to: field)
    }

    /// 从偏好回读（真源始终是偏好，不在这里缓存）
    func refresh() {
        field.stringValue = "\(preferences.maxBytes / Self.bytesPerMegabyte)"
        rowView.update(title: nil, subtitle: preferences.maxBytes == ClipboardCapacityUsage.unlimited
                       ? Self.unlimitedSubtitle : Self.subtitle)
    }

    @objc private func changed() {
        commit()
    }

    /// 失焦也算提交：改完容量直接点别处不会丢设置
    func controlTextDidEndEditing(_ obj: Notification) {
        commit()
    }

    /// 提交并回显；非法输入拦住、回填原值并把原因写进副标题
    /// - Returns: 是否通过校验
    @discardableResult
    func commit() -> Bool {
        switch ClipboardCapacityUsage.parsedMegabytes(from: field.stringValue,
                                                      bytesPerMegabyte: Self.bytesPerMegabyte) {
        case .success(let bytes):
            // 回车提交与失焦提交可能连着触发两次：值没变就不再跑一轮清理（避免重复扫库 / 重复刷新）
            let changed = bytes != preferences.maxBytes
            preferences.maxBytes = bytes
            refresh()
            if changed { onCommit() }
            return true
        case .failure(let reason):
            field.stringValue = "\(preferences.maxBytes / Self.bytesPerMegabyte)"
            rowView.update(title: nil, subtitle: reason.message)
            logger.warning("剪贴板最大容量输入被拒绝：\(field.stringValue.trimmingCharacters(in: .whitespaces))（\(reason.message)）")
            return false
        }
    }
}
