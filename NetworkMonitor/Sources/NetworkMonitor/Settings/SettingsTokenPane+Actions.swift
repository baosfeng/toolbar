import AppKit
import NetworkMonitorCore

// MARK: - Token 用量设置页（动作）

/// 目录切换与索引维护动作 —— 从主文件拆出（选择面板 + 二次确认 + 回执文案是一组内聚逻辑）
extension SettingsTokenPane {

    // MARK: - 目录

    /// 选择数据目录：选完先校验是目录，再落偏好并换扫描器（不自动重扫，动作分开）
    @objc func chooseSourceDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "选择 DSH 会话目录"
        panel.prompt = "选择"
        panel.message = "选择包含会话日志的 sessions 目录（其下是各项目目录）"
        let current = controller.diagnostics.directoryPath
        if !current.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: current, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard SettingsTokenController.isValidDirectory(url) else {
            presentAlert(title: "无法使用该目录", message: "选中的位置不是可用的文件夹。", style: .warning)
            return
        }
        // 目录里没有 sessions 结构时仍然允许——用户可能就是刚建的；
        // 但要说清现状，别让他以为「选了就有数据」
        let warning = controller.setDirectory(url)
        refresh()
        if let warning {
            presentAlert(title: "暂不可用", message: warning, style: .warning)
        }
        logger.info("设置页切换 Token 数据目录：" + url.path)
    }

    /// 恢复默认目录（清掉显式偏好，环境变量 / 默认路径重新参与解析）
    @objc func resetSourceDirectory() {
        _ = controller.setDirectory(nil)
        refresh()
        logger.info("设置页恢复默认 Token 数据目录")
    }

    // MARK: - 维护

    /// 重新扫描：先二次确认（全量清理不可撤销），确认后清空 + 全量重建，回执写回维护行副标题
    @objc func requestRescan() {
        let diagnostics = controller.diagnostics
        let alert = NSAlert()
        alert.messageText = "重新扫描 Token 索引？"
        alert.informativeText = "将清空本机索引（事件与扫描记录），再从会话文件全量重建。"
            + "会话文件本身不会被修改。\n\n数据目录：" + diagnostics.directoryPath
        alert.alertStyle = .warning
        alert.addButton(withTitle: "重新扫描")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.keyEquivalent = ""
        alert.buttons.last?.keyEquivalent = "\r"
        alert.buttons.first?.setAccessibilityLabel("确认清空索引并全量重建")
        alert.buttons.last?.setAccessibilityLabel("取消，不重新扫描")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        startRebuild(scope: .full, pendingText: "正在清空并重建索引…")
    }

    /// 清理历史数据：先选范围（含实时条数）→ 按规模二次确认 → 清理并立即重扫
    ///
    /// 两步交互本身在 SettingsTokenPurgePrompt（选项与文案口径），这里只接线：
    /// 只给「确认吗」的旧实现到了第三方机器上就是一次盲删。
    @objc func requestClearHistory() {
        let preview: (HarnessRebuildScope) -> Int = { [weak self] scope in
            self?.controller.purgePreview(scope: scope) ?? -1
        }
        guard let plan = SettingsTokenPurgePrompt.plan(preview: preview,
                                                       directoryPath: controller.diagnostics.directoryPath)
        else { return }
        startRebuild(scope: plan.scope, pendingText: "正在清理" + plan.title + "并重新扫描…")
        logger.info("设置页 Token 清理历史数据：" + plan.title + "（预览 " + String(plan.eventCount) + " 条）")
    }

    /// 发起重建并在维护行上显示过程与回执
    ///
    /// 「清理历史数据」复用同一入口（清理后必然紧接一次扫描）：
    /// 分开实现会出现「清理了但没扫」的中间态，用户下次开面板才发现数据没了。
    private func startRebuild(scope: HarnessRebuildScope, pendingText: String) {
        rescanButton.isEnabled = false
        clearButton.isEnabled = false
        maintenanceRow.update(title: nil, subtitle: pendingText)
        controller.rebuild(scope: scope) { [weak self] receipt in
            guard let self else { return }
            self.refresh()
            if let receipt {
                // 维护行副标题只有一行宽（约 360pt）：完整 summaryText 会被截成「…跳过」，
                // 而「删了多少 / 索引了多少」正是本轮要交代的两件事，因此只在这行写这两项 + 耗时，
                // 完整回执进日志。
                self.maintenanceRow.update(title: nil, subtitle: SettingsTokenReceiptText.compact(receipt))
                self.logger.info("设置页 Token 重建完成：" + receipt.summaryText)
            } else {
                let reason = self.controller.diagnostics.zstdNote ?? "数据源不可用，未能重建"
                self.maintenanceRow.update(title: nil, subtitle: "重建失败：" + reason)
                self.logger.warning("设置页 Token 重建失败：" + reason)
            }
        }
    }

    /// 统一的一次性提示（不叠加窗口：设置页已有足够上下文）
    private func presentAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
