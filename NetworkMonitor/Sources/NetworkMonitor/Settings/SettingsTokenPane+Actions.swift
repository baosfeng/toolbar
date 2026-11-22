import AppKit
import NetworkMonitorCore

// MARK: - Token 用量设置页（动作）

/// 索引维护（重扫 / 清理历史）与二次确认 —— 从主文件拆出；
/// 来源开关 / 目录选择 / 自动监控的动作在 SettingsTokenSourcesCard.swift（跟「数据来源」卡同处一案）。
extension SettingsTokenPane {

    // MARK: - 维护

    /// 维护动作的目标来源（nil = 全部来源）
    var maintenanceTarget: TokenSourceID? {
        let index = sourceControl.indexOfSelectedItem - 1
        return TokenSourceID.allCases.indices.contains(index) ? TokenSourceID.allCases[index] : nil
    }

    var maintenanceTargetName: String { maintenanceTarget?.displayName ?? "全部来源" }

    @objc func maintenanceSourceChanged() {
        maintenanceRow.update(title: nil, subtitle: "目标：" + maintenanceTargetName
            + "。重新扫描会先清空索引再全量重建；清理历史可选范围并自动重扫")
    }

    /// 维护动作的执行范围：选中了来源就只动这个来源（scope 真的带 source，不是只改文案）
    var maintenanceScope: HarnessRebuildScope {
        maintenanceTarget.map { HarnessRebuildScope.source($0, .full) } ?? .full
    }

    /// 重新扫描：先二次确认（清空不可撤销），确认后按**选中来源**清空并重建
    @objc func requestRescan() {
        let diagnostics = controller.diagnostics
        let scope = maintenanceScope
        let alert = NSAlert()
        alert.messageText = "重新扫描 Token 索引？"
        alert.informativeText = "目标来源：" + maintenanceTargetName + "（只动这个来源的索引）"
            + "\n将清空该范围的索引（事件与扫描记录），再从会话文件重建。会话文件本身不会被修改。"
            + "\n\n数据目录：" + diagnostics.directoryPath
        alert.alertStyle = .warning
        alert.addButton(withTitle: "重新扫描")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.keyEquivalent = ""
        alert.buttons.last?.keyEquivalent = "\r"
        alert.buttons.first?.setAccessibilityLabel("确认清空索引并全量重建")
        alert.buttons.last?.setAccessibilityLabel("取消，不重新扫描")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        logger.info("设置页 Token 重新扫描：" + scope.displayName)
        startRebuild(scope: scope, pendingText: "正在清空「" + maintenanceTargetName + "」并重建…")
    }

    /// 清理历史数据：先选范围（含实时条数）→ 按规模二次确认 → 清理并立即重扫
    @objc func requestClearHistory() {
        let preview: (HarnessRebuildScope) -> Int = { [weak self] scope in
            self?.controller.purgePreview(scope: scope) ?? -1
        }
        guard let plan = SettingsTokenPurgePrompt.plan(preview: preview,
                                                       directoryPath: controller.diagnostics.directoryPath,
                                                       source: maintenanceTarget)
        else { return }
        // 清完立即重扫同一范围：只清不扫会留下「清了却永远不回来」的假清空
        startRebuild(scope: plan.scope,
                     pendingText: "正在清理「" + (plan.sourceName ?? "全部来源") + "」" + plan.title + "并重扫…")
        logger.info("设置页 Token 清理历史数据：" + plan.title
                    + "（预览 " + String(plan.eventCount) + " 条，范围 " + plan.scope.displayName + "）")
    }

    /// 发起重建并在维护行上显示过程与回执
    private func startRebuild(scope: HarnessRebuildScope, pendingText: String) {
        rescanButton.isEnabled = false
        clearButton.isEnabled = false
        maintenanceRow.update(title: nil, subtitle: pendingText)
        controller.rebuild(scope: scope) { [weak self] receipt in
            guard let self else { return }
            self.refresh()
            if let receipt {
                self.maintenanceRow.update(title: nil, subtitle: SettingsTokenReceiptText.compact(receipt))
                self.logger.info("设置页 Token 重建完成：" + receipt.summaryText)
            } else {
                let reason = self.controller.diagnostics.zstdNote ?? "数据源不可用，未能重建"
                self.maintenanceRow.update(title: nil, subtitle: "重建失败：" + reason)
                self.logger.warning("设置页 Token 重建失败：" + reason)
            }
        }
    }
}
