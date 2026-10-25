import AppKit
import NetworkMonitorCore

// MARK: - 接收目录切换

/// 接收目录切换 — 从主文件拆出（新增「选择…」后主文件逼近单文件上限）
///
/// 目录的建目录、切换与偏好落库都在 `TransferService.setReceiveDirectory(_:)` 内完成，
/// 设置页只负责选择目录与刷新占用，不直接读写偏好。
extension SettingsTransferPane {

    /// 选择接收目录 — 成功后重算占用统计
    @objc func chooseReceiveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "选择接收目录"
        panel.prompt = "选择"
        panel.directoryURL = service.receiveDirectory
        guard panel.runModal() == .OK, let url = panel.url,
              url.standardizedFileURL != service.receiveDirectory.standardizedFileURL else { return }

        chooseButton?.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            let result = await self.service.setReceiveDirectory(url)
            self.chooseButton?.isEnabled = true
            switch result {
            case .success:
                self.refreshUsage()
            case .failure(let error):
                self.logger.error("接收目录切换失败：\(error.message)")
                self.presentDirectoryError(error.message)
            }
        }
    }

    /// 目录副标题：路径 + 占用统计（占用刷新完再拼一次）
    ///
    /// 放宽为 internal：主文件的 `refreshUsage()` 也要用它。
    func directorySubtitle() -> String {
        "\(Self.displayPath(service.receiveDirectory)) · \(usageText)"
    }

    /// 目录不可用时的提示（权限不足 / 目标不可写）
    private func presentDirectoryError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "无法使用该目录"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.alertStyle = .warning
        alert.runModal()
    }
}
