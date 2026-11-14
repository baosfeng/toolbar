#if DEBUG
import AppKit

// MARK: - 设置窗口快照（仅 DEBUG）

/// 设置窗口六页 × 深浅色离屏渲染 — 复用菜单面板同一套渲染通道
///
/// 触发方式与菜单面板一致：`NM_SNAPSHOT_DIR=/tmp/nm-shots <可执行>`，
/// 产出 `settings-<分类>-{light,dark}.png`（760×540，与原型画布一致）。
@MainActor
enum SettingsSnapshot {

    /// 首次打开取证：新建一个窗口，**不做任何显式布局**就渲染根视图
    ///
    /// 用户反馈「第一次进设置页中间有大片空白，再进一次就好了」，
    /// 差别就在这里——`capture` 那条路径会先 `layoutSubtreeIfNeeded()`。
    /// 这张图用来复现首次路径（每次快照都会重出，作为回归证据）。
    static func captureFirstOpen(directory: URL, settings: SettingsWindow?) {
        guard let settings else { return }
        guard let fresh = settings.makeFreshForFirstOpenProbe() else { return }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            let url = directory.appendingPathComponent("settings-firstopen-general-\(suffix).png")
            MenuPanelSnapshot.render(view: fresh, size: SettingsStyle.windowSize,
                                     appearanceName: appearance, to: url)
        }
    }

    /// 渲染全部设置页
    static func capture(directory: URL, settings: SettingsWindow?) {
        guard let settings else { return }
        let size = SettingsStyle.windowSize
        for section in SettingsSection.allCases {
            guard let view = settings.prepareForSnapshot(section) else { continue }
            // 快照时把工具条卡片的控件勾选态与偏好真值打出来：核对两者一致
            if section == .capture, let capture = settings.currentPaneForSnapshot as? SettingsCapturePane {
                // 探针按页实例取控件状态：勾选态与偏好真值必须一致
                capture.debugLogToolBarControlStates("snapshot")
            }
            // 含通知事件行的页（额度 / 截图 / 剪贴板 / 互传 / 通用）：开关与下拉的选中项
            // 离屏渲染看不出来，状态判定以 settings-notification-events-<页>.txt 为准
            // （见踩坑记录「离屏快照看不出开关状态」）
            if let host = settings.currentPaneForSnapshot as? SettingsNotificationEventHosting {
                host.notificationCard.debugLogStates(section.fileSuffix)
            }
            // 外观页的玻璃开关同样是 NSSwitch：图上只看版式，三项状态判定以
            // settings-appearance-states.txt 为准（偏好真值 / 控件勾选态并排 + 一致判定）
            if section == .appearance,
               let appearancePane = settings.currentPaneForSnapshot as? SettingsAppearancePane {
                appearancePane.debugLogAppearanceControlStates("snapshot")
            }
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let suffix = appearance == .aqua ? "light" : "dark"
                let url = directory.appendingPathComponent(
                    "settings-\(section.fileSuffix)-\(suffix).png")
                MenuPanelSnapshot.render(view: view, size: size,
                                         appearanceName: appearance, to: url)
            }
        }
        // 截图页滚动到底部：本轮新增的「识别」卡与「保存」卡（输出格式 / JPEG 质量）在首屏之外，
        // 单独出一组作为其可见性证据；版式基线仍是上面的首屏图
        captureScrolledCapture(directory: directory, settings: settings)
        captureScrolledClipboard(directory: directory, settings: settings)
        captureScrolledNotifications(directory: directory, settings: settings)
        captureNotificationCards(directory: directory, settings: settings)
        captureFirstOpen(directory: directory, settings: settings)
    }

    /// 截图页滚动到底部（识别卡 / 保存卡在首屏之外，单独出一组作为可见性证据）
    static func captureScrolledCapture(directory: URL, settings: SettingsWindow?) {
        guard let settings else { return }
        // 滚到「距底部 340pt」：识别卡与保存卡（输出格式 / JPEG 质量 / 目录）同时进视野
        guard let view = settings.prepareForSnapshotScrolled(toBottomOffset: 340, section: .capture) else {
            return
        }
        writeCaptureScrollMetrics(directory: directory, settings: settings)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            let url = directory.appendingPathComponent("settings-capture-cards-\(suffix).png")
            MenuPanelSnapshot.render(view: view, size: SettingsStyle.windowSize,
                                     appearanceName: appearance, to: url)
        }
    }

    /// 截图页滚动度量：核对「保存卡确实在首屏之外」而不靠肉眼
    private static func writeCaptureScrollMetrics(directory: URL, settings: SettingsWindow) {
        guard let documentHeight = settings.snapshotScrollDocumentHeight else { return }
        let viewportHeight = SettingsStyle.windowSize.height - SettingsStyle.contentInset * 2
        let overflow = max(0, documentHeight - viewportHeight)
        let text = """
        capture_page_document_pt = \(Int(documentHeight.rounded()))
        capture_page_viewport_pt = \(Int(viewportHeight.rounded()))
        capture_page_scroll_needed_pt = \(Int(overflow.rounded()))
        save_and_ocr_cards_on_first_screen = \(overflow <= 0)
        """
        try? text.write(to: directory.appendingPathComponent("settings-capture-metrics.txt"),
                        atomically: true, encoding: .utf8)
    }

    /// 剪贴板页滚动到底部（存储卡在首屏之外，单独出一组作为可见性证据）
    ///
    /// 版式基线仍是首屏图；这张只证明「存储」卡在实际页面上完整可见、深浅色都不压字。
    static func captureScrolledClipboard(directory: URL, settings: SettingsWindow?) {
        guard let settings else { return }
        guard let view = settings.prepareForSnapshotScrolledToBottom(.clipboard) else { return }
        writeClipboardScrollMetrics(directory: directory, settings: settings)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            let url = directory.appendingPathComponent("settings-clipboard-storage-\(suffix).png")
            MenuPanelSnapshot.render(view: view, size: SettingsStyle.windowSize,
                                     appearanceName: appearance, to: url)
        }
    }

    /// 通知与音效页滚动到底部（音效库 / 重置卡在首屏之外，单独出一组作为可见性证据）
    static func captureScrolledNotifications(directory: URL, settings: SettingsWindow?) {
        guard let settings else { return }
        guard let view = settings.prepareForSnapshotScrolledToBottom(.notifications) else { return }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            let url = directory.appendingPathComponent("settings-notifications-library-\(suffix).png")
            MenuPanelSnapshot.render(view: view, size: SettingsStyle.windowSize,
                                     appearanceName: appearance, to: url)
        }
    }

    /// 各功能页的「通知事件卡」可见性证据
    ///
    /// 事件行已下沉到各功能页（额度 / 截图 / 剪贴板 / 互传 / 通用），在页内位置靠后，
    /// 首屏图看不出它在哪一段；这里按卡片实际坐标滚一段，图能直接证明「行确实在这页」。
    /// 只对含事件卡的页出图（协议 `SettingsNotificationEventHosting`），其余页跳过。
    static func captureNotificationCards(directory: URL, settings: SettingsWindow?) {
        guard let settings else { return }
        for section in SettingsSection.allCases {
            guard let view = settings.prepareForSnapshotShowingNotificationCard(section),
                  let host = settings.currentPaneForSnapshot as? SettingsNotificationEventHosting else {
                continue
            }
            host.notificationCard.debugLogStates("card-\(section.fileSuffix)")
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let suffix = appearance == .aqua ? "light" : "dark"
                let url = directory.appendingPathComponent(
                    "settings-\(section.fileSuffix)-notification-card-\(suffix).png")
                MenuPanelSnapshot.render(view: view, size: SettingsStyle.windowSize,
                                         appearanceName: appearance, to: url)
            }
        }
    }

    /// 写剪贴板页的滚动度量（文档高 / 视口高 / 需要下滚多少），供 review 核对「存储卡在首屏之外」而不靠肉眼
    private static func writeClipboardScrollMetrics(directory: URL, settings: SettingsWindow) {
        guard let documentHeight = settings.snapshotScrollDocumentHeight else { return }
        let viewportHeight = SettingsStyle.windowSize.height - SettingsStyle.contentInset * 2
        let overflow = max(0, documentHeight - viewportHeight)
        let text = """
        clipboard_page_document_pt = \(Int(documentHeight.rounded()))
        clipboard_page_viewport_pt = \(Int(viewportHeight.rounded()))
        clipboard_page_scroll_needed_pt = \(Int(overflow.rounded()))
        storage_card_on_first_screen = \(overflow <= 0)
        """
        try? text.write(to: directory.appendingPathComponent("settings-clipboard-metrics.txt"),
                        atomically: true, encoding: .utf8)
    }
}
#endif
