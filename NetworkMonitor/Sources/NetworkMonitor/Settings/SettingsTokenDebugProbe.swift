#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - Token 用量页的取证探针（仅 DEBUG）
//
// 单独成文件的原因：族行数门禁按 `<类名>+<职责>.swift` 聚合，探针塞进
// SettingsTokenPane 的扩展会直接顶破 SettingsTokenPane 族基线；
// 探针只在 DEBUG 下编译，与页面版式无关。

extension SettingsTokenPane {

    /// 把「清理历史数据」两个弹窗的状态按**生产同一套函数**打成文本
    ///
    /// NSAlert 拍不到离屏图，所以范围选项、各范围将删除条数与确认框正文只能以文本取证；
    /// 这里调用的都是生产函数（`HarnessPurgeRange` / `SettingsTokenPurgePrompt`），
    /// 因此它反映的就是真机点开时看到的同一份文案。
    func debugPurgePromptStates() -> [String] {
        var lines: [String] = []
        lines.append("purge_range_options = "
                     + HarnessPurgeRange.allCases.map(\.title).joined(separator: " | "))
        lines.append("purge_range_default = " + HarnessPurgeRange.defaultRange.title)
        for range in HarnessPurgeRange.allCases {
            let count = controller.purgePreview(scope: range.scope)
            lines.append("purge_preview[" + range.title + "] = " + String(count) + " 条 · "
                         + SettingsTokenPurgePrompt.eventCountText(count))
        }
        let count = controller.purgePreview(scope: .sinceDays(30))
        lines.append("confirm_title[近 30 天] = 确认清理" + HarnessPurgeRange.days30.confirmationText + "？")
        lines.append("confirm_body[近 30 天] = 将删除 " + String(count) + " 条事件，并同时删除对应的扫描记录，"
                     + "随后从会话文件重新扫描。")
        lines.append("confirm_first_button = 清理 " + (count > 0 ? String(count) + " 条" : ""))
        lines.append("token_page_maintenance_subtitle = " + maintenanceRow.debugSubtitleText)
        return lines
    }
}
#endif
