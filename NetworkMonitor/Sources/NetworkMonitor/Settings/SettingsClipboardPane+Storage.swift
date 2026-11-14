import AppKit
import NetworkMonitorCore

// MARK: - 剪贴板设置页（图片存储）

/// 图片存储卡 — 占用统计 + 打开目录 + 清空（对标 OneClip P2-1）
///
/// 拆出原因：主文件已贴着单文件 15 KiB 上限，而「统计 → 打开 → 清空」是一组内聚的存储管理动作。
/// 跨文件访问：`usageLabel` / `usageDetailLabel` / `openDirectoryButton` / `clearStorageButton` /
/// `storageActionRow` / `settingsDelegate` 由主文件放宽为 internal，仅供本扩展使用。
///
/// 口径：
/// - 大小一律走既有 `SystemDetailFormatting.byteCountText`，不另写单位换算；
/// - 目录路径与条数同屏显示，避免只有大小看不出「有多少文件」；
/// - 清空必须二次确认（NSAlert），确认后由组合根复用既有清空 + 孤儿清扫，页面只做刷新与反馈。
extension SettingsClipboardPane {

    /// 管理行的默认副标题（清空后临时改成结果文案，下次刷新复位）
    static let storageActionSubtitle = "清空会删除历史条目与残留图片文件，收藏项及其图片保留"

    /// 构建「存储」卡（占用 + 目录 + 两个动作）
    func buildStorageCard() {
        usageLabel.font = SettingsTheme.rowValueFont
        usageLabel.textColor = SettingsTheme.textPrimary
        usageLabel.alignment = .right
        usageLabel.setContentHuggingPriority(.required, for: .horizontal)
        usageLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        usageDetailLabel.font = SettingsTheme.rowSubtitleFont
        usageDetailLabel.textColor = SettingsTheme.textSecondary
        usageDetailLabel.lineBreakMode = .byTruncatingMiddle
        usageDetailLabel.maximumNumberOfLines = 1
        // 路径很长：让它先被压缩（行名必须完整），过宽时省略中间段而不是把左侧「目录」压成省略号
        usageDetailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        usageDetailLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        usageDetailLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 360).isActive = true

        let usageRow = SettingsRowView(title: "图片占用")
        usageRow.trailingStack.addArrangedSubview(usageLabel)
        let detailRow = SettingsRowView(title: "目录")
        detailRow.trailingStack.addArrangedSubview(usageDetailLabel)

        openDirectoryButton = SettingsLinkButton.make("打开图片目录", target: self,
                                                       action: #selector(openImageDirectory))
        openDirectoryButton.setAccessibilityLabel("打开图片目录")
        clearStorageButton = SettingsLinkButton.make("清空…", target: self,
                                                      action: #selector(requestClearImageStorage),
                                                      color: SettingsTheme.destructive)
        clearStorageButton.setAccessibilityLabel("清空图片存储（需二次确认）")

        let actionRow = SettingsRowView(title: "管理", subtitle: Self.storageActionSubtitle)
        actionRow.trailingStack.addArrangedSubview(openDirectoryButton)
        actionRow.trailingStack.addArrangedSubview(clearStorageButton)
        storageActionRow = actionRow

        let card = SettingsCardView()
        [usageRow, detailRow, actionRow].forEach(card.addRow)
        page.addCard(card, sectionTitle: "存储")
    }

    /// 刷新占用与条数（切页 / 窗口重新显示 / 清空后都调用；每次现算，不缓存）
    ///
    /// - Parameter provided: 已拿到的当前目录占用。`refresh()` 里只扫一次目录，
    ///   同一次页刷新内存储卡与页头胶囊共用这一份读数；传 nil 时自己现取。
    func refreshStorageCard(usage provided: ClipboardStorageUsage.Summary? = nil) {
        let usage = provided ?? settingsDelegate?.settingsClipboardImageUsage() ?? ClipboardStorageUsage.empty
        let sizeText = SystemDetailFormatting.byteCountText(usage.byteCount)
        usageLabel.stringValue = sizeText
        let countText = "\(usage.fileCount) 个文件"
        if usage.exists {
            usageDetailLabel.stringValue = countText + " · " + ClipboardImageStore.directory.path
            usageDetailLabel.setAccessibilityLabel("图片目录，共 \(countText)，占用 \(sizeText)")
        } else {
            // 目录还没建（从未采集过图片）：不报错，说明现状并给出路径
            usageDetailLabel.stringValue = "尚未创建 · " + ClipboardImageStore.directory.path
            usageDetailLabel.setAccessibilityLabel("图片目录尚未创建")
        }
        usageDetailLabel.toolTip = ClipboardImageStore.directory.path
        // 没有文件时「清空」没有意义：置灰保留（不是消失），说明仍可见
        clearStorageButton.isEnabled = usage.fileCount > 0
        // 上次清理的结果文案复位，避免停留在旧状态
        storageActionRow?.update(title: nil, subtitle: Self.storageActionSubtitle)
        // 页头胶囊吃同一个文件数：清空后胶囊也跟着归零，不用等下次切页
        refreshHeaderChip(usage: usage)
    }

    // MARK: 动作

    /// 打开图片目录：目录不存在时先建出来再打开，避免点了没反应
    @objc func openImageDirectory() {
        let directory = ClipboardImageStore.directory
        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                logger.error("图片目录创建失败：\(error.localizedDescription)")
                return
            }
        }
        NSWorkspace.shared.open(directory)
    }

    /// 清空图片存储：先弹二次确认，确认后由组合根复用既有清空 + 孤儿清扫
    ///
    /// 确认弹窗的键位口径：按钮顺序保持「清空 / 取消」（NSAlert 的 Esc 恒落到第二个按钮＝取消），
    /// 同时把回车显式绑到「取消」，破坏性动作只接受鼠标显式点击，不会因为顺手回车而清空。
    @objc func requestClearImageStorage() {
        let usage = settingsDelegate?.settingsClipboardImageUsage() ?? ClipboardStorageUsage.empty
        let sizeText = SystemDetailFormatting.byteCountText(usage.byteCount)
        let alert = NSAlert()
        alert.messageText = "清空剪贴板图片存储？"
        alert.informativeText = "将删除 \(usage.fileCount) 个图片文件（\(sizeText)）以及对应的历史条目，"
            + "收藏项及其图片会保留。此操作不可撤销。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        // 回车默认落在「取消」：清空按钮摘掉默认键位，只有鼠标点在它上面才会执行
        alert.buttons.first?.keyEquivalent = ""
        alert.buttons.last?.keyEquivalent = "\r"
        // 读屏：两个按钮各自说清后果（按钮标题太短，光念「清空」不足以判断代价）
        alert.buttons.first?.setAccessibilityLabel("确认清空图片存储与历史条目，收藏项保留")
        alert.buttons.last?.setAccessibilityLabel("取消，不清空")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        // 委托缺位不能假装「本来就没有可清空的」：那是把失败包装成成功
        guard let delegate = settingsDelegate else {
            logger.error("清空图片存储失败：设置页未拿到委托（组合根未注入）")
            refreshStorageCard()
            storageActionRow?.update(title: nil, subtitle: "清空失败：设置页未接上清空链路")
            return
        }
        let result = delegate.settingsDidRequestClearImageStorage()
        refreshStorageCard()
        // 结果落在管理行副标题：不弹二次窗口，也不需要新的状态行
        storageActionRow?.update(title: nil,
                                 subtitle: result.isNoop
                                 ? "没有可清空的图片存储"
                                 : "已清空：删除 \(result.deletedItems) 条历史、\(result.removedFiles) 个文件（收藏保留）")
        logger.info("设置页清空图片存储：条目 \(result.deletedItems)，文件 \(result.removedFiles)")
    }
}
