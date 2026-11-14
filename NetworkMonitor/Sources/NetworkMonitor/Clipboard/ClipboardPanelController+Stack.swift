import AppKit
import NetworkMonitorCore

// MARK: - Paste Stack 动作与首次引导（从面板控制器拆出，守住单文件体积上限）

extension ClipboardPanelController {

    /// 放宽 internal：跨文件被按键拦截调用
    func pushSelectedToStack() {
        guard let item = selectedItem else { return }
        // 无辅助功能权限：不得静默，给出文案与跳转入口
        guard stack.push(id: item.id) else {
            // 入栈失败（缺辅助功能权限）：给失败音，避免「点了没反应」的错觉
            feedback.sound.play(.error)
            content.showHint("缺少辅助功能权限，无法使用 Paste Stack，请前往系统设置授权")
            return
        }
        content.showHint("已加入 Paste Stack（第 \(stack.remainingCount) 项）")
    }

    /// 放宽 internal：跨文件被按键拦截调用
    func clearStack() {
        stack.removeAll()
        content.showHint("Paste Stack 已清空")
    }

    // MARK: 首次引导

    /// 首次引导态判定：未被引导过 + 历史为空
    ///
    /// 标记走偏好层的一次性开关（hasGuidedClipboardAccess）。数据库里已有条目即视为已引导并落标记：
    /// 老用户升级上来不该被引导页挡住，日后手动清空历史也不该又冒出引导页。
    /// 放宽 internal：跨文件被打开面板 / 过滤刷新调用
    func refreshGuideState() {
        let hotKey = preferences.panelToggleHotKey.displayString
        guard !preferences.hasGuidedClipboardAccess else {
            content.updateGuideState(visible: false, toggleHotKey: hotKey)
            return
        }
        guard items.isEmpty else {
            preferences.hasGuidedClipboardAccess = true
            content.updateGuideState(visible: false, toggleHotKey: hotKey)
            return
        }
        content.updateGuideState(visible: true, toggleHotKey: hotKey)
    }

    /// 关闭引导态：写标记后不再出现（视图侧只负责回调，不碰偏好）
    func panelViewDidDismissGuide(_ view: ClipboardPanelView) {
        preferences.hasGuidedClipboardAccess = true
        content.updateGuideState(visible: false,
                                 toggleHotKey: preferences.panelToggleHotKey.displayString)
        logger.info("剪贴板首次引导已关闭，后续不再展示")
    }
}