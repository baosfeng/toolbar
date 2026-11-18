import AppKit
import NetworkMonitorCore

// MARK: - 额度 Provider 设置页（实例增删改 + 恢复提醒）

/// 实例管理与恢复提醒控件 —— 从主文件拆出（主文件负责页面结构与行渲染）
///
/// 交互选择：新增 / 重命名用 `NSAlert` + 单行输入，删除用带 destructive 按钮的确认框。
/// 理由：实例管理是低频操作，弹窗比行内嵌入第三种编辑态更省版面，也不会和
/// 「凭据编辑 / 清除确认」两种既有行内态互相打架。
extension SettingsProvidersPane {

    // MARK: - 新增实例

    @objc func addInstanceTapped(_ sender: NSButton) {
        // tag 是 `kindOrder` 的有界索引（见 makeAddInstanceRow），不做跨模块共享
        guard kindOrder.indices.contains(sender.tag) else { return }
        promptAddInstance(kindID: kindOrder[sender.tag])
    }

    func promptAddInstance(kindID: String) {
        let kindTitle = kindTitle(kindID)
        guard let input = promptText(title: "新增 \(kindTitle) 实例",
                                     message: "实例名用小写字母、数字或连字符（如 work），会拼进凭据键与环境变量名。",
                                     placeholder: "work") else { return }
        let slug = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !slug.isEmpty else {
            showToast("实例名不能为空")
            return
        }
        let title = "\(kindTitle)（\(slug)）"
        switch monitor.addInstance(kindID: kindID, slug: slug, title: title) {
        case .success:
            rebuildKindCard(kindID)
            showToast("已新增实例「\(title)」，填 Key 后即可查询")
        case .failure(let error):
            showToast(error.userMessage)
        }
    }

    // MARK: - 重命名

    func promptRename(_ instance: BillingInstance) {
        guard let input = promptText(title: "重命名实例",
                                     message: "只改显示名，凭据与提醒状态都会保留。",
                                     placeholder: instance.title) else { return }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showToast("名称不能为空")
            return
        }
        monitor.renameInstance(instance.id, title: trimmed)
        rebuildKindCard(instance.kindID)
        showToast("已重命名")
    }

    // MARK: - 删除实例

    func confirmDeleteInstance(_ instance: BillingInstance) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "删除实例「\(instance.title)」？"
        alert.informativeText = "将同时清除该实例的凭据与额度提醒状态，且无法撤销。"
            + "删除后该实例的额度卡会从面板消失。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        monitor.removeInstance(instance.id)
        rows[instance.id] = nil
        rebuildKindCard(instance.kindID)
        showToast("已删除实例并清除其凭据")
    }


    // MARK: - 输入框

    /// 单行文本输入（取消返回 nil）
    private func promptText(title: String, message: String, placeholder: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = placeholder
        field.font = SettingsTheme.rowValueFont
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
}
